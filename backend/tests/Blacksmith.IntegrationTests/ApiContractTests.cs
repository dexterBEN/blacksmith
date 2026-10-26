using System.Net;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using Blacksmith.Infrastructure.Persistence;
using Blacksmith.Domain.Entities;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Data.Sqlite;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace Blacksmith.IntegrationTests;

public sealed class ApiContractTests : IDisposable
{
    private readonly SqliteConnection _connection = new("Data Source=:memory:");
    private readonly ApiFactory _factory;
    private readonly HttpClient _client;

    public ApiContractTests()
    {
        _connection.Open();
        _factory = new ApiFactory(_connection);
        _client = _factory.CreateClient(new WebApplicationFactoryClientOptions
        {
            BaseAddress = new Uri("https://localhost"), AllowAutoRedirect = false
        });
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<BlacksmithDbContext>();
        db.Database.EnsureCreated();
        db.Designs.Add(new DesignEntity { Id = LegacyDesign.Id, Name = LegacyDesign.Name });
        db.SaveChanges();
    }

    [Fact]
    public async Task Resource_crud_preserves_json_status_codes_location_and_creation_time()
    {
        var before = DateTime.UtcNow;
        var createdResponse = await _client.PostAsJsonAsync("/resources",
            new { name = "  Local bucket  ", x = -2, y = 7, type = "  gcp.storage.bucket  " });
        Assert.Equal(HttpStatusCode.Created, createdResponse.StatusCode);
        var created = await ReadResource(createdResponse);
        var id = created.GetProperty("id").GetGuid();
        var createdAt = created.GetProperty("createdAtUtc").GetDateTime();
        Assert.NotEqual(Guid.Empty, id);
        Assert.InRange(createdAt, before, DateTime.UtcNow);
        Assert.Equal("Local bucket", created.GetProperty("name").GetString());
        Assert.Equal("gcp.storage.bucket", created.GetProperty("type").GetString());
        Assert.Equal(-2, created.GetProperty("x").GetInt32());
        Assert.Equal(7, created.GetProperty("y").GetInt32());
        Assert.Equal($"https://localhost/resources/{id}", createdResponse.Headers.Location?.ToString());

        var foundResponse = await _client.GetAsync(createdResponse.Headers.Location);
        Assert.Equal(HttpStatusCode.OK, foundResponse.StatusCode);
        var found = await ReadResource(foundResponse);
        Assert.Equal(id, found.GetProperty("id").GetGuid());

        var updatedResponse = await _client.PutAsJsonAsync($"/resources/{id}",
            new { name = "  Renamed  ", x = 3, y = -5, type = "  generic  " });
        Assert.Equal(HttpStatusCode.OK, updatedResponse.StatusCode);
        var updated = await ReadResource(updatedResponse);
        Assert.Equal(id, updated.GetProperty("id").GetGuid());
        Assert.Equal(createdAt, updated.GetProperty("createdAtUtc").GetDateTime());
        Assert.Equal("Renamed", updated.GetProperty("name").GetString());
        Assert.Equal("generic", updated.GetProperty("type").GetString());
        Assert.Equal(3, updated.GetProperty("x").GetInt32());
        Assert.Equal(-5, updated.GetProperty("y").GetInt32());

        var list = await _client.GetFromJsonAsync<JsonElement>("/resources");
        Assert.Equal(id, Assert.Single(list.EnumerateArray()).GetProperty("id").GetGuid());
        var deleted = await _client.DeleteAsync($"/resources/{id}");
        Assert.Equal(HttpStatusCode.NoContent, deleted.StatusCode);
        Assert.Empty(await deleted.Content.ReadAsStringAsync());
        Assert.Equal(HttpStatusCode.NotFound, (await _client.GetAsync($"/resources/{id}")).StatusCode);
        Assert.Empty((await _client.GetFromJsonAsync<JsonElement>("/resources")).EnumerateArray());
        Assert.Empty(_factory.Cloud.Calls);
    }

    [Fact]
    public async Task Resource_list_is_ordered_by_creation_time_descending()
    {
        var older = new ResourceEntity { Id = Guid.NewGuid(), DesignId = LegacyDesign.Id, Name = "Old", Type = "generic",
            CreatedAtUtc = new DateTime(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc) };
        var newer = new ResourceEntity { Id = Guid.NewGuid(), DesignId = LegacyDesign.Id, Name = "New", Type = "generic",
            X = 1, CreatedAtUtc = older.CreatedAtUtc.AddDays(1) };
        using (var scope = _factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<BlacksmithDbContext>();
            db.Resources.AddRange(older, newer);
            await db.SaveChangesAsync();
        }
        var list = await _client.GetFromJsonAsync<JsonElement>("/resources");
        Assert.Equal(new[] { newer.Id, older.Id },
            list.EnumerateArray().Select(item => item.GetProperty("id").GetGuid()));
    }

    [Theory]
    [InlineData("", "bucket", "Name is required")]
    [InlineData("   ", "bucket", "Name is required")]
    [InlineData("valid", "", "Type is required")]
    [InlineData("valid", "   ", "Type is required")]
    [InlineData("", "", "Name is required")]
    public async Task Resource_validation_preserves_errors_and_precedes_missing_id_lookup(
        string name, string type, string error)
    {
        foreach (var method in new[] { HttpMethod.Post, HttpMethod.Put })
        {
            using var request = new HttpRequestMessage(method,
                method == HttpMethod.Post ? "/resources" : $"/resources/{Guid.NewGuid()}")
            { Content = JsonContent.Create(new { name, type, x = 0, y = 0 }) };
            var response = await _client.SendAsync(request);
            Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
            Assert.Equal(error, (await response.Content.ReadFromJsonAsync<JsonElement>())
                .GetProperty("error").GetString());
        }
        Assert.Empty(_factory.Cloud.Calls);
    }

    [Theory]
    [InlineData("get")]
    [InlineData("put")]
    [InlineData("delete")]
    public async Task Unknown_resource_ids_return_404(string method)
    {
        using var request = new HttpRequestMessage(new HttpMethod(method), $"/resources/{Guid.NewGuid()}");
        if (method == "put") request.Content = JsonContent.Create(new { name = "valid", type = "valid" });
        Assert.Equal(HttpStatusCode.NotFound, (await _client.SendAsync(request)).StatusCode);
    }

    [Fact]
    public async Task Non_guid_resource_id_does_not_match_route()
    {
        Assert.Equal(HttpStatusCode.NotFound, (await _client.GetAsync("/resources/not-a-guid")).StatusCode);
    }

    [Theory]
    [InlineData("null")]
    [InlineData("{\"name\":null,\"type\":\"bucket\"}")]
    [InlineData("{")]
    public async Task Invalid_json_or_null_body_keeps_automatic_api_validation(string json)
    {
        var response = await _client.PostAsync("/resources", new StringContent(json, Encoding.UTF8, "application/json"));
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.True((await response.Content.ReadFromJsonAsync<JsonElement>()).TryGetProperty("errors", out _));
    }

    [Fact]
    public async Task Cloud_routes_keep_existing_payloads_and_query_parameters()
    {
        var ping = await _client.GetFromJsonAsync<JsonElement>("/cloud_services/ping");
        Assert.Equal("CloudServices backend is alive 🚀", ping.GetProperty("message").GetString());
        Assert.Empty(_factory.Cloud.Calls);
        var response = await _client.PostAsync(
            "/cloud_services/create-bucket?projectId=test-project&bucketName=test-bucket", null);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("Bucket test-bucket create in project test-project",
            (await response.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("message").GetString());
        Assert.Equal(("test-project", "test-bucket"), Assert.Single(_factory.Cloud.Calls));
    }

    [Fact]
    public async Task Missing_cloud_query_parameters_return_400_without_provider_call()
    {
        var response = await _client.PostAsync("/cloud_services/create-bucket", null);
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Empty(_factory.Cloud.Calls);
    }

    private static async Task<JsonElement> ReadResource(HttpResponseMessage response)
    {
        var value = await response.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal(new[] { "createdAtUtc", "id", "name", "type", "x", "y" },
            value.EnumerateObject().Select(property => property.Name).Order());
        return value;
    }

    public void Dispose()
    {
        _client.Dispose();
        _factory.Dispose();
        _connection.Dispose();
    }
}
