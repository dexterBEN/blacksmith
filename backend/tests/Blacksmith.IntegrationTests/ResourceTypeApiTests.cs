using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Blacksmith.Infrastructure.Persistence;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace Blacksmith.IntegrationTests;

public sealed class ResourceTypeApiTests : IDisposable
{
    private static readonly Guid StorageId = new("10000000-0000-0000-0000-000000000002");
    private static readonly Guid DatabaseId = new("10000000-0000-0000-0000-000000000003");
    private readonly SqliteConnection _connection = new("Data Source=:memory:");
    private readonly ApiFactory _factory;
    private readonly HttpClient _client;

    public ResourceTypeApiTests()
    {
        _connection.Open();
        _factory = new ApiFactory(_connection);
        _client = _factory.CreateClient(new WebApplicationFactoryClientOptions { BaseAddress = new Uri("https://localhost") });
        using var scope = _factory.Services.CreateScope();
        scope.ServiceProvider.GetRequiredService<BlacksmithDbContext>().Database.EnsureCreated();
    }

    [Fact]
    public async Task Catalog_contains_six_stable_generic_entries_and_dedicated_dtos()
    {
        var list = await _client.GetFromJsonAsync<JsonElement>("/resource-types");
        Assert.Equal(new[] { "database", "gateway", "load-balancer", "network", "storage", "virtual-machine" },
            list.EnumerateArray().Select(item => item.GetProperty("code").GetString()));
        var expected = new Dictionary<string, (string IdSuffix, string Name, string Category)>
        {
            ["virtual-machine"] = ("001", "Virtual Machine", "Compute"),
            ["storage"] = ("002", "Storage", "Storage"),
            ["database"] = ("003", "Database", "Data"),
            ["network"] = ("004", "Network", "Networking"),
            ["gateway"] = ("005", "Gateway", "Networking"),
            ["load-balancer"] = ("006", "Load Balancer", "Networking")
        };
        foreach (var item in list.EnumerateArray())
        {
            Assert.Equal(new[] { "category", "code", "displayName", "id" }, item.EnumerateObject().Select(x => x.Name).Order());
            var definition = expected[item.GetProperty("code").GetString()!];
            Assert.Equal(Guid.Parse("10000000-0000-0000-0000-000000000" + definition.IdSuffix), item.GetProperty("id").GetGuid());
            Assert.Equal(definition.Name, item.GetProperty("displayName").GetString());
            Assert.Equal(definition.Category, item.GetProperty("category").GetString());
            var byId = await _client.GetFromJsonAsync<JsonElement>($"/resource-types/{item.GetProperty("id").GetGuid()}");
            Assert.Equal(item.ToString(), byId.ToString());
        }
    }

    [Theory]
    [InlineData("00000000-0000-0000-0000-000000000000")]
    [InlineData("20000000-0000-0000-0000-000000000001")]
    [InlineData("not-a-guid")]
    public async Task Unknown_or_invalid_type_id_returns_404(string id) =>
        Assert.Equal(HttpStatusCode.NotFound, (await _client.GetAsync($"/resource-types/{id}")).StatusCode);

    [Theory]
    [InlineData("POST", "/resource-types")]
    [InlineData("PUT", "/resource-types/10000000-0000-0000-0000-000000000002")]
    [InlineData("DELETE", "/resource-types/10000000-0000-0000-0000-000000000002")]
    public async Task Catalog_is_read_only(string method, string url)
    {
        using var request = new HttpRequestMessage(new HttpMethod(method), url)
        { Content = JsonContent.Create(new { code = "new-type" }) };
        Assert.Equal(HttpStatusCode.MethodNotAllowed, (await _client.SendAsync(request)).StatusCode);
    }

    [Theory]
    [InlineData("storage", "10000000-0000-0000-0000-000000000002")]
    [InlineData(" storage ", "10000000-0000-0000-0000-000000000002")]
    [InlineData("database", "10000000-0000-0000-0000-000000000003")]
    [InlineData("gcp.storage.bucket", null)]
    [InlineData("Storage", null)]
    [InlineData("generic", null)]
    public async Task Legacy_create_preserves_response_and_only_resolves_exact_codes(string text, string? expectedId)
    {
        var response = await _client.PostAsJsonAsync("/resources", new { name = "Resource", type = text, x = -3, y = 8 });
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal(new[] { "createdAtUtc", "id", "name", "type", "x", "y" }, body.EnumerateObject().Select(x => x.Name).Order());
        Assert.Equal(text.Trim(), body.GetProperty("type").GetString());
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<BlacksmithDbContext>();
        var resource = await db.Resources.SingleAsync();
        Assert.Equal(expectedId is null ? (Guid?)null : Guid.Parse(expectedId), resource.ResourceTypeId);
        Assert.Equal(text.Trim(), resource.Type);
    }

    [Fact]
    public async Task Explicit_classification_survives_legacy_updates_and_changed_type_is_resolved_again()
    {
        var response = await _client.PostAsJsonAsync("/resources",
            new { name = "Bucket", type = "gcp.storage.bucket", resourceTypeId = StorageId });
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var id = (await response.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetGuid();
        var resourceUrl = $"/resources/{id}";
        Assert.Equal(HttpStatusCode.OK, (await _client.PutAsJsonAsync(resourceUrl,
            new { name = "Renamed", type = "gcp.storage.bucket" })).StatusCode);
        Assert.Equal(StorageId, await CurrentTypeId());
        Assert.Equal(HttpStatusCode.OK, (await _client.PutAsJsonAsync(resourceUrl,
            new { name = "Database", type = "database" })).StatusCode);
        Assert.Equal(DatabaseId, await CurrentTypeId());
        Assert.Equal(HttpStatusCode.OK, (await _client.PutAsJsonAsync(resourceUrl,
            new { name = "Unknown", type = "custom.type" })).StatusCode);
        Assert.Null(await CurrentTypeId());

        async Task<Guid?> CurrentTypeId()
        {
            using var scope = _factory.Services.CreateScope();
            return (await scope.ServiceProvider.GetRequiredService<BlacksmithDbContext>().Resources.SingleAsync()).ResourceTypeId;
        }
    }

    [Fact]
    public async Task Missing_type_returns_404_without_creating_owner_or_mutating_existing_resource()
    {
        var missing = Guid.NewGuid();
        Assert.Equal(HttpStatusCode.NotFound, (await _client.PostAsJsonAsync("/resources",
            new { name = "Resource", type = "generic", resourceTypeId = missing })).StatusCode);
        using (var scope = _factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<BlacksmithDbContext>();
            Assert.Empty(await db.Designs.ToListAsync());
            Assert.Empty(await db.Resources.ToListAsync());
        }
        var created = await _client.PostAsJsonAsync("/resources", new { name = "Original", type = "storage" });
        var id = (await created.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetGuid();
        var update = await _client.PutAsJsonAsync($"/resources/{id}",
            new { name = "Changed", type = "generic", resourceTypeId = missing });
        Assert.Equal(HttpStatusCode.NotFound, update.StatusCode);
        Assert.Equal("Resource type not found.", (await update.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("error").GetString());
        var found = await _client.GetFromJsonAsync<JsonElement>($"/resources/{id}");
        Assert.Equal("Original", found.GetProperty("name").GetString());
        Assert.Equal("storage", found.GetProperty("type").GetString());
    }

    [Fact]
    public async Task Contradictory_known_type_and_reference_return_400()
    {
        var response = await _client.PostAsJsonAsync("/resources",
            new { name = "Resource", type = "storage", resourceTypeId = DatabaseId });
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal("Type and resourceTypeId refer to different catalog entries",
            (await response.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("error").GetString());
        Assert.Empty((await _client.GetFromJsonAsync<JsonElement>("/resources")).EnumerateArray());
    }

    public void Dispose()
    {
        Assert.Empty(_factory.Cloud.Calls);
        _client.Dispose();
        _factory.Dispose();
        _connection.Dispose();
    }
}
