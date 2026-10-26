using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Blacksmith.Domain.Entities;
using Blacksmith.Infrastructure.Persistence;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace Blacksmith.IntegrationTests;

public sealed class DesignApiTests : IDisposable
{
    private readonly SqliteConnection _connection = new("Data Source=:memory:");
    private readonly ApiFactory _factory;
    private readonly HttpClient _client;

    public DesignApiTests()
    {
        _connection.Open();
        _factory = new ApiFactory(_connection);
        _client = _factory.CreateClient(new WebApplicationFactoryClientOptions { BaseAddress = new Uri("https://localhost") });
        using var scope = _factory.Services.CreateScope();
        scope.ServiceProvider.GetRequiredService<BlacksmithDbContext>().Database.EnsureCreated();
    }

    [Fact]
    public async Task Empty_design_crud_has_dedicated_contract_and_never_calls_cloud()
    {
        var response = await _client.PostAsJsonAsync("/designs", new { name = " Canvas ", description = " Notes " });
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var created = await response.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal(new[] { "createdAtUtc", "description", "id", "name", "updatedAtUtc" },
            created.EnumerateObject().Select(x => x.Name).Order());
        var id = created.GetProperty("id").GetGuid();
        Assert.Equal($"https://localhost/designs/{id}", response.Headers.Location!.ToString());
        Assert.Equal("Canvas", created.GetProperty("name").GetString());
        Assert.Equal("Notes", created.GetProperty("description").GetString());
        Assert.Equal(created.GetProperty("createdAtUtc").GetDateTime(), created.GetProperty("updatedAtUtc").GetDateTime());
        Assert.Equal(HttpStatusCode.OK, (await _client.GetAsync($"/designs/{id}")).StatusCode);
        Assert.Single((await _client.GetFromJsonAsync<JsonElement>("/designs")).EnumerateArray());
        Assert.Empty((await _client.GetFromJsonAsync<JsonElement>($"/designs/{id}/resources")).EnumerateArray());

        var update = await _client.PutAsJsonAsync($"/designs/{id}", new { name = " Renamed ", description = " " });
        Assert.Equal(HttpStatusCode.OK, update.StatusCode);
        var updated = await update.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal("Renamed", updated.GetProperty("name").GetString());
        Assert.Equal(JsonValueKind.Null, updated.GetProperty("description").ValueKind);
        Assert.Equal(created.GetProperty("createdAtUtc").GetDateTime(), updated.GetProperty("createdAtUtc").GetDateTime());
        Assert.True(updated.GetProperty("updatedAtUtc").GetDateTime() >= created.GetProperty("updatedAtUtc").GetDateTime());
        Assert.Equal(HttpStatusCode.NoContent, (await _client.DeleteAsync($"/designs/{id}")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await _client.GetAsync($"/designs/{id}")).StatusCode);
        Assert.Empty((await _client.GetFromJsonAsync<JsonElement>("/designs")).EnumerateArray());
        Assert.Empty(_factory.Cloud.Calls);
    }

    [Theory]
    [InlineData("get")]
    [InlineData("put")]
    [InlineData("delete")]
    [InlineData("resources")]
    public async Task Unknown_design_returns_404(string method)
    {
        var url = $"/designs/{Guid.NewGuid()}";
        var response = method switch
        {
            "put" => await _client.PutAsJsonAsync(url, new { name = "Valid" }),
            "delete" => await _client.DeleteAsync(url),
            "resources" => await _client.GetAsync(url + "/resources"),
            _ => await _client.GetAsync(url)
        };
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("  ")]
    public async Task Invalid_design_names_return_400(string? name)
    {
        Assert.Equal(HttpStatusCode.BadRequest, (await _client.PostAsJsonAsync("/designs", new { name })).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await _client.PutAsJsonAsync($"/designs/{Guid.NewGuid()}", new { name })).StatusCode);
    }

    [Fact]
    public async Task Overlong_design_name_returns_400()
    {
        Assert.Equal(HttpStatusCode.BadRequest,
            (await _client.PostAsJsonAsync("/designs", new { name = new string('x', 201) })).StatusCode);
    }

    [Fact]
    public async Task Multiple_resources_are_filtered_by_owner_and_nonempty_delete_returns_409_without_cascade()
    {
        var first = await CreateDesign("First");
        var second = await CreateDesign("Second");
        var resourceIds = new List<Guid>();
        foreach (var owner in new[] { first, first, second })
        {
            var response = await _client.PostAsJsonAsync("/resources", new { designId = owner, name = "Bucket", type = "generic", x = resourceIds.Count });
            Assert.Equal(HttpStatusCode.Created, response.StatusCode);
            resourceIds.Add((await response.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetGuid());
        }
        var firstResources = await _client.GetFromJsonAsync<JsonElement>($"/designs/{first}/resources");
        Assert.Equal(2, firstResources.GetArrayLength());
        Assert.All(firstResources.EnumerateArray(), item => Assert.Equal(first, item.GetProperty("designId").GetGuid()));
        Assert.Single((await _client.GetFromJsonAsync<JsonElement>($"/designs/{second}/resources")).EnumerateArray());
        var conflict = await _client.DeleteAsync($"/designs/{first}");
        Assert.Equal(HttpStatusCode.Conflict, conflict.StatusCode);
        Assert.Equal("Cannot delete a design that contains resources.",
            (await conflict.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("error").GetString());
        Assert.Equal(HttpStatusCode.OK, (await _client.GetAsync($"/designs/{first}")).StatusCode);
        Assert.Equal(3, (await _client.GetFromJsonAsync<JsonElement>("/resources")).GetArrayLength());
        foreach (var id in resourceIds.Take(2))
            Assert.Equal(HttpStatusCode.NoContent, (await _client.DeleteAsync($"/resources/{id}")).StatusCode);
        Assert.Equal(HttpStatusCode.NoContent, (await _client.DeleteAsync($"/designs/{first}")).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await _client.GetAsync($"/resources/{resourceIds[2]}")).StatusCode);
        Assert.Empty(_factory.Cloud.Calls);
    }

    [Fact]
    public async Task Missing_owner_rejects_create_and_reassignment_without_changing_existing_resource()
    {
        var owner = await CreateDesign("Owner");
        var response = await _client.PostAsJsonAsync("/resources", new { designId = owner, name = "Original", type = "generic" });
        var id = (await response.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetGuid();
        foreach (var missing in new[] { Guid.NewGuid(), Guid.Empty })
        {
            Assert.Equal(HttpStatusCode.NotFound, (await _client.PostAsJsonAsync("/resources",
                new { designId = missing, name = "New", type = "generic" })).StatusCode);
            Assert.Equal(HttpStatusCode.NotFound, (await _client.PutAsJsonAsync($"/resources/{id}",
                new { designId = missing, name = "Changed", type = "generic" })).StatusCode);
        }
        var resource = Assert.Single((await _client.GetFromJsonAsync<JsonElement>($"/designs/{owner}/resources")).EnumerateArray());
        Assert.Equal("Original", resource.GetProperty("name").GetString());
        Assert.Single((await _client.GetFromJsonAsync<JsonElement>("/resources")).EnumerateArray());
    }

    [Fact]
    public async Task Legacy_create_uses_stable_owner_and_legacy_update_preserves_explicit_owner()
    {
        var explicitOwner = await CreateDesign("Explicit");
        var created = await _client.PostAsJsonAsync("/resources", new { name = "Legacy", type = "generic" });
        Assert.Equal(HttpStatusCode.Created, created.StatusCode);
        Assert.Single((await _client.GetFromJsonAsync<JsonElement>($"/designs/{LegacyDesign.Id}/resources")).EnumerateArray());
        var explicitResource = await _client.PostAsJsonAsync("/resources",
            new { name = "Owned", type = "generic", designId = explicitOwner });
        var id = (await explicitResource.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetGuid();
        Assert.Equal(HttpStatusCode.OK, (await _client.PutAsJsonAsync($"/resources/{id}",
            new { name = "Renamed", type = "generic" })).StatusCode);
        var resource = Assert.Single((await _client.GetFromJsonAsync<JsonElement>($"/designs/{explicitOwner}/resources")).EnumerateArray());
        Assert.Equal(id, resource.GetProperty("id").GetGuid());
        var other = await CreateDesign("Other");
        Assert.Equal(HttpStatusCode.OK, (await _client.PutAsJsonAsync($"/resources/{id}",
            new { name = "Moved", type = "generic", designId = other })).StatusCode);
        Assert.Empty((await _client.GetFromJsonAsync<JsonElement>($"/designs/{explicitOwner}/resources")).EnumerateArray());
        Assert.Single((await _client.GetFromJsonAsync<JsonElement>($"/designs/{other}/resources")).EnumerateArray());
    }

    [Fact]
    public async Task Invalid_legacy_request_does_not_create_owner_and_renamed_legacy_owner_is_preserved()
    {
        Assert.Equal(HttpStatusCode.BadRequest, (await _client.PostAsJsonAsync("/resources", new { name = "", type = "generic" })).StatusCode);
        Assert.Empty((await _client.GetFromJsonAsync<JsonElement>("/designs")).EnumerateArray());
        var created = await _client.PostAsJsonAsync("/resources", new { name = "One", type = "generic" });
        var id = (await created.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetGuid();
        Assert.Equal(HttpStatusCode.OK, (await _client.PutAsJsonAsync($"/designs/{LegacyDesign.Id}", new { name = "My canvas" })).StatusCode);
        Assert.Equal(HttpStatusCode.Created, (await _client.PostAsJsonAsync("/resources", new { name = "Two", type = "generic", x = 1 })).StatusCode);
        Assert.Equal("My canvas", (await _client.GetFromJsonAsync<JsonElement>($"/designs/{LegacyDesign.Id}")).GetProperty("name").GetString());
        Assert.Equal(HttpStatusCode.NoContent, (await _client.DeleteAsync($"/resources/{id}")).StatusCode);
    }

    [Fact]
    public async Task Database_rejects_orphan_and_loaded_children_cannot_be_cascaded()
    {
        var owner = await CreateDesign("Owner");
        await _client.PostAsJsonAsync("/resources", new { name = "Child", type = "generic", designId = owner });
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<BlacksmithDbContext>();
        var design = await db.Designs.Include(x => x.Resources).SingleAsync(x => x.Id == owner);
        Assert.Single(design.Resources);
        Assert.Throws<InvalidOperationException>(() => db.Designs.Remove(design));
        db.ChangeTracker.Clear();
        db.Resources.Add(new ResourceEntity { Id = Guid.NewGuid(), DesignId = Guid.NewGuid(), Name = "Orphan", Type = "generic" });
        await Assert.ThrowsAsync<DbUpdateException>(() => db.SaveChangesAsync());
        db.ChangeTracker.Clear();
        Assert.Equal(1, await db.Resources.CountAsync());
        Assert.Equal(1, await db.Designs.CountAsync());
    }

    private async Task<Guid> CreateDesign(string name)
    {
        var response = await _client.PostAsJsonAsync("/designs", new { name });
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        return (await response.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetGuid();
    }

    public void Dispose()
    {
        Assert.Empty(_factory.Cloud.Calls);
        _client.Dispose();
        _factory.Dispose();
        _connection.Dispose();
    }
}
