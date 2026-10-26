using System.Net;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using Blacksmith.Domain.Entities;
using Blacksmith.Infrastructure.Persistence;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace Blacksmith.IntegrationTests;

public sealed class ConfiguredResourceApiTests : IDisposable
{
    private const string Body = """{"name":"Display label","type":"gcp.storage.bucket","resourceTypeId":"10000000-0000-0000-0000-000000000002","x":-7,"y":12,"configuration":{"schemaVersion":1,"configuration":{"projectId":"example-project-123","bucketName":"blacksmith-example-assets","location":"europe-west9"}}}""";
    private readonly SqliteConnection _connection = new("Data Source=:memory:");
    private readonly ApiFactory _factory;
    private readonly HttpClient _client;
    public ConfiguredResourceApiTests()
    {
        _connection.Open();
        _factory = new ApiFactory(_connection);
        _client = _factory.CreateClient(new WebApplicationFactoryClientOptions { BaseAddress = new Uri("https://localhost") });
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<BlacksmithDbContext>();
        db.Database.EnsureCreated();
        db.Designs.Add(new DesignEntity { Id = LegacyDesign.Id, Name = LegacyDesign.Name });
        db.SaveChanges();
    }

    [Fact]
    public async Task Canonical_create_read_noop_edit_and_legacy_shapes_are_distinct()
    {
        var id = Guid.NewGuid();
        var created = await Write(id, Body, "If-None-Match", "*");
        Assert.Equal(HttpStatusCode.Created, created.StatusCode);
        Assert.Equal("created", created.Headers.GetValues("X-Resource-Write-Outcome").Single());
        Assert.Null(created.Headers.ETag);
        var aggregate = await created.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal(new[] { "configuration", "configurationState", "createdAtUtc", "designId", "id", "name", "resourceTypeId", "revision", "type", "x", "y" }, aggregate.EnumerateObject().Select(x => x.Name).Order());
        Assert.Equal(id, aggregate.GetProperty("id").GetGuid());
        Assert.Equal(LegacyDesign.Id, aggregate.GetProperty("designId").GetGuid());
        Assert.Equal(1, aggregate.GetProperty("revision").GetInt64());
        Assert.Equal("Display label", aggregate.GetProperty("name").GetString());
        Assert.Equal("validated", aggregate.GetProperty("configurationState").GetString());
        Assert.Equal(JsonValueKind.Object, aggregate.GetProperty("configuration").GetProperty("configuration").ValueKind);
        var read = await _client.GetAsync($"/resources/{id}?include=configuration");
        var tag = read.Headers.ETag!.Tag;
        Assert.Equal(await created.Content.ReadAsStringAsync(), await read.Content.ReadAsStringAsync());
        var noop = await Write(id, Body, "If-Match", tag);
        Assert.Equal(HttpStatusCode.OK, noop.StatusCode);
        Assert.Equal("unchanged", noop.Headers.GetValues("X-Resource-Write-Outcome").Single());
        Assert.Equal(1, (await noop.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("revision").GetInt64());
        var edit = await Write(id, Body.Replace("example-assets", "edited-assets"), "If-Match", tag);
        Assert.Equal(HttpStatusCode.OK, edit.StatusCode);
        Assert.Equal("updated", edit.Headers.GetValues("X-Resource-Write-Outcome").Single());
        Assert.Equal(2, (await edit.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("revision").GetInt64());
        Assert.Equal(HttpStatusCode.PreconditionFailed, (await Write(id, Body, "If-Match", tag)).StatusCode);
        Assert.Equal(HttpStatusCode.PreconditionFailed, (await Write(id, Body, "If-None-Match", "*")).StatusCode);
        var legacy = await _client.GetFromJsonAsync<JsonElement>($"/resources/{id}");
        Assert.Equal(new[] { "createdAtUtc", "id", "name", "type", "x", "y" }, legacy.EnumerateObject().Select(x => x.Name).Order());
        var list = await _client.GetFromJsonAsync<JsonElement>($"/designs/{LegacyDesign.Id}/resources?include=configuration");
        Assert.Equal(1, list.GetArrayLength());
        Assert.Equal(id, list[0].GetProperty("id").GetGuid());
    }

    [Theory]
    [InlineData(null, null, 428)]
    [InlineData("If-None-Match", "not-star", 400)]
    [InlineData("If-Match", "*", 400)]
    [InlineData("If-Match", "W/\"revision\"", 400)]
    [InlineData("If-Match", "\"wrong-resource-r1\"", 400)]
    public async Task Missing_or_invalid_preconditions_never_write(string? header, string? value, int status)
    {
        var response = await Write(Guid.NewGuid(), Body, header, value);
        Assert.Equal(status, (int)response.StatusCode);
        Assert.True((await response.Content.ReadFromJsonAsync<JsonElement>()).TryGetProperty("code", out _));
        await EmptyDatabase();
    }

    [Theory]
    [InlineData("{")]
    [InlineData("null")]
    [InlineData("[]")]
    [InlineData("{}")]
    public async Task Malformed_or_incomplete_create_leaves_no_resource(string body)
    {
        Assert.Equal(HttpStatusCode.BadRequest, (await Write(Guid.NewGuid(), body, "If-None-Match", "*")).StatusCode);
        await EmptyDatabase();
    }

    [Fact]
    public async Task Strict_body_rejects_secret_override_duplicates_overflow_depth_and_size_without_echo()
    {
        foreach (var body in new[]
        {
            Body.Replace("europe-west9", "US"),
            Body.Replace("\"x\":-7", "\"x\":2147483648"),
            Body.Replace("\"x\":-7", "\"x\":-7,\"X\":0"),
            Body.Replace("\"name\":", "\"designId\":\"DO_NOT_ECHO_FIXTURE\",\"name\":"),
            Body.Replace("\"location\":", "\"private_key\":\"DO_NOT_ECHO_FIXTURE\",\"location\":"),
            Body.Replace("\"europe-west9\"", new string('[', 12) + "0" + new string(']', 12))
        })
        {
            var response = await Write(Guid.NewGuid(), body, "If-None-Match", "*");
            Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
            Assert.DoesNotContain("DO_NOT_ECHO_FIXTURE", await response.Content.ReadAsStringAsync());
        }
        Assert.Equal(HttpStatusCode.RequestEntityTooLarge, (await Write(Guid.NewGuid(), Body.Replace("Display label", new string('x', 17000)), "If-None-Match", "*")).StatusCode);
        await EmptyDatabase();
    }

    private Task<HttpResponseMessage> Write(Guid id, string body, string? header, string? value)
    {
        var request = new HttpRequestMessage(HttpMethod.Put, $"/designs/{LegacyDesign.Id}/resources/{id}")
            { Content = new StringContent(body, Encoding.UTF8, "application/json") };
        if (header is not null) request.Headers.TryAddWithoutValidation(header, value);
        return _client.SendAsync(request);
    }
    private async Task EmptyDatabase()
    {
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<BlacksmithDbContext>();
        Assert.Equal(0, await db.Resources.CountAsync());
        Assert.Equal(0, await db.ResourceConfigurations.CountAsync());
    }
    public void Dispose()
    {
        try { Assert.Empty(_factory.Cloud.Calls); }
        finally { _client.Dispose(); _factory.Dispose(); _connection.Dispose(); }
    }
}
