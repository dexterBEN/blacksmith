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

public sealed class ResourceConfigurationApiTests : IDisposable
{
    private const string Valid = """{"schemaVersion":1,"configuration":{"projectId":"example-project-123","bucketName":"blacksmith-example-assets","location":"europe-west9"}}""";
    private readonly SqliteConnection _connection = new("Data Source=:memory:");
    private readonly ApiFactory _factory;
    private readonly HttpClient _client;

    public ResourceConfigurationApiTests()
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
    public async Task Create_replace_and_read_are_canonical_objects_without_metadata_changes()
    {
        var id = await Resource();
        var before = await _client.GetStringAsync($"/resources/{id}");
        var first = await Put(id, Valid);
        Assert.Equal(HttpStatusCode.OK, first.StatusCode);
        var body = await first.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal(new[] { "configuration", "resourceId", "schemaVersion" }, body.EnumerateObject().Select(x => x.Name).Order());
        Assert.Equal(id, body.GetProperty("resourceId").GetGuid());
        Assert.Equal(1, body.GetProperty("schemaVersion").GetInt32());
        var config = body.GetProperty("configuration");
        Assert.Equal(JsonValueKind.Object, config.ValueKind);
        Assert.Equal(6, config.EnumerateObject().Count());
        Assert.Equal("STANDARD", config.GetProperty("storageClass").GetString());
        Assert.True(config.GetProperty("uniformBucketLevelAccess").GetBoolean());
        Assert.Equal("enforced", config.GetProperty("publicAccessPrevention").GetString());
        Assert.False(config.TryGetProperty("softDeleteRetentionDays", out _));
        Assert.Equal(await first.Content.ReadAsStringAsync(), await _client.GetStringAsync($"/resources/{id}/configuration"));
        Assert.Equal(HttpStatusCode.OK, (await Put(id, Valid.Replace("example-assets", "replacement-assets"))).StatusCode);
        using var read = JsonDocument.Parse(await _client.GetStringAsync($"/resources/{id}/configuration"));
        Assert.Equal("blacksmith-replacement-assets", read.RootElement.GetProperty("configuration").GetProperty("bucketName").GetString());
        Assert.Equal(before, await _client.GetStringAsync($"/resources/{id}"));
        using var scope = _factory.Services.CreateScope();
        Assert.Equal(1, await scope.ServiceProvider.GetRequiredService<BlacksmithDbContext>().ResourceConfigurations.CountAsync());
    }

    [Fact]
    public async Task Unknown_resource_and_missing_configuration_are_404_without_implicit_create()
    {
        var id = await Resource();
        Assert.Equal(HttpStatusCode.NotFound, (await _client.GetAsync($"/resources/{id}/configuration")).StatusCode);
        var unknown = Guid.NewGuid();
        Assert.Equal(HttpStatusCode.NotFound, (await _client.GetAsync($"/resources/{unknown}/configuration")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await Put(unknown, Valid)).StatusCode);
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<BlacksmithDbContext>();
        Assert.Equal(1, await db.Resources.CountAsync());
        Assert.Empty(await db.ResourceConfigurations.ToArrayAsync());
    }

    [Theory]
    [InlineData("compute")]
    [InlineData("generic-storage")]
    [InlineData("wrong-catalog")]
    public async Task Persisted_type_and_optional_catalog_are_authoritative(string mode)
    {
        var id = await Resource(mode == "compute" ? "gcp.compute.instance" : mode == "generic-storage" ? "storage" : "gcp.storage.bucket");
        using (var scope = _factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<BlacksmithDbContext>();
            var resource = await db.Resources.SingleAsync();
            resource.ResourceTypeId = (await db.ResourceTypes.SingleAsync(x => x.Code == (mode == "wrong-catalog" ? "virtual-machine" : "storage"))).Id;
            await db.SaveChangesAsync();
        }
        Assert.Equal(HttpStatusCode.BadRequest, (await Put(id, Valid)).StatusCode);
        using var verify = _factory.Services.CreateScope();
        Assert.Empty(await verify.ServiceProvider.GetRequiredService<BlacksmithDbContext>().ResourceConfigurations.ToArrayAsync());
    }

    [Theory]
    [InlineData("{")]
    [InlineData("null")]
    [InlineData("[]")]
    [InlineData("{\"schemaVersion\":2,\"configuration\":{}}")]
    [InlineData("{\"schemaVersion\":1,\"configuration\":[]}")]
    [InlineData("{\"schemaVersion\":1,\"configuration\":{}}")]
    public async Task Malformed_or_unsupported_requests_preserve_saved_configuration(string json)
    {
        var id = await Resource();
        Assert.Equal(HttpStatusCode.OK, (await Put(id, Valid)).StatusCode);
        var before = await _client.GetStringAsync($"/resources/{id}/configuration");
        Assert.Equal(HttpStatusCode.BadRequest, (await Put(id, json)).StatusCode);
        Assert.Equal(before, await _client.GetStringAsync($"/resources/{id}/configuration"));
    }

    [Fact]
    public async Task Strict_fields_duplicates_depth_and_payload_limit_reject_without_echo_or_mutation()
    {
        var id = await Resource();
        Assert.Equal(HttpStatusCode.OK, (await Put(id, Valid)).StatusCode);
        var before = await _client.GetStringAsync($"/resources/{id}/configuration");
        var invalid = new[]
        {
            Valid.Replace("europe-west9", "US"),
            Valid.Replace("\"location\":", "\"private_key\":\"DO_NOT_ECHO_FIXTURE\",\"location\":"),
            Valid.Replace("\"location\":", "\"softDeleteRetentionDays\":7,\"location\":"),
            Valid.Replace("\"schemaVersion\":1", "\"schemaVersion\":1,\"schemaVersion\":1"),
            Valid.Replace("\"location\":\"europe-west9\"", "\"location\":\"europe-west9\",\"Location\":\"us-central1\""),
            Valid.Replace("\"configuration\":", "\"configuration\":{},\"configuration\":"),
            Valid.Replace("\"configuration\":", "\"resourceId\":\"DO_NOT_ECHO_FIXTURE\",\"configuration\":"),
            Valid.Replace("\"europe-west9\"", new string('[', 12) + "0" + new string(']', 12))
        };
        foreach (var json in invalid)
        {
            var response = await Put(id, json);
            Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
            Assert.DoesNotContain("DO_NOT_ECHO_FIXTURE", await response.Content.ReadAsStringAsync());
        }
        Assert.Equal(HttpStatusCode.RequestEntityTooLarge,
            (await Put(id, Valid.Replace("blacksmith-example-assets", new string('x', 17000)))).StatusCode);
        Assert.Equal(before, await _client.GetStringAsync($"/resources/{id}/configuration"));
    }

    [Fact]
    public async Task Legacy_metadata_cannot_erase_or_retype_configured_resource_but_unconfigured_type_changes_work()
    {
        var id = await Resource();
        Assert.Equal(HttpStatusCode.OK, (await Put(id, Valid)).StatusCode);
        var saved = await _client.GetStringAsync($"/resources/{id}/configuration");
        var renamed = await _client.PutAsJsonAsync($"/resources/{id}", new { name = "Renamed", type = "gcp.storage.bucket", x = 4, y = 5 });
        Assert.Equal(HttpStatusCode.OK, renamed.StatusCode);
        Assert.Equal(saved, await _client.GetStringAsync($"/resources/{id}/configuration"));
        Assert.Equal(HttpStatusCode.BadRequest, (await _client.PutAsJsonAsync($"/resources/{id}", new { name = "Wrong", type = "gcp.compute.instance", x = 0, y = 0 })).StatusCode);
        Guid compute;
        using (var scope = _factory.Services.CreateScope())
            compute = scope.ServiceProvider.GetRequiredService<BlacksmithDbContext>().ResourceTypes.Single(x => x.Code == "virtual-machine").Id;
        Assert.Equal(HttpStatusCode.BadRequest, (await _client.PutAsJsonAsync($"/resources/{id}", new { name = "Wrong", type = "gcp.storage.bucket", resourceTypeId = compute, x = 0, y = 0 })).StatusCode);
        var other = await Resource();
        Assert.Equal(HttpStatusCode.OK, (await _client.PutAsJsonAsync($"/resources/{other}", new { name = "Allowed", type = "custom.legacy", x = 0, y = 0 })).StatusCode);
        Assert.Equal(saved, await _client.GetStringAsync($"/resources/{id}/configuration"));
        Assert.Equal(HttpStatusCode.NoContent, (await _client.DeleteAsync($"/resources/{id}")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await _client.GetAsync($"/resources/{id}/configuration")).StatusCode);
        using var verify = _factory.Services.CreateScope();
        Assert.Empty(await verify.ServiceProvider.GetRequiredService<BlacksmithDbContext>().ResourceConfigurations.ToArrayAsync());
    }

    [Theory]
    [InlineData(2, "{}")]
    [InlineData(1, "[]")]
    [InlineData(1, "{\"private_key\":\"DO_NOT_ECHO_FIXTURE\"}")]
    public async Task Historical_unsupported_payload_is_not_exposed_and_explicit_valid_put_can_replace_it(int version, string json)
    {
        var id = await Resource();
        using (var scope = _factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<BlacksmithDbContext>();
            db.ResourceConfigurations.Add(new ResourceConfiguration { ResourceId = id, SchemaVersion = version, Configuration = json });
            await db.SaveChangesAsync();
        }
        var response = await _client.GetAsync($"/resources/{id}/configuration");
        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
        Assert.DoesNotContain("DO_NOT_ECHO_FIXTURE", await response.Content.ReadAsStringAsync());
        Assert.Equal(HttpStatusCode.OK, (await Put(id, Valid)).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await _client.GetAsync($"/resources/{id}/configuration")).StatusCode);
    }

    private Task<HttpResponseMessage> Put(Guid id, string json) => _client.PutAsync($"/resources/{id}/configuration", new StringContent(json, Encoding.UTF8, "application/json"));

    private async Task<Guid> Resource(string type = "gcp.storage.bucket")
    {
        var response = await _client.PostAsJsonAsync("/resources", new { name = "Fixture resource", type, x = 3, y = 2, designId = LegacyDesign.Id });
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        return (await response.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetGuid();
    }

    public void Dispose()
    {
        Assert.Empty(_factory.Cloud.Calls);
        _client.Dispose(); _factory.Dispose(); _connection.Dispose();
    }
}
