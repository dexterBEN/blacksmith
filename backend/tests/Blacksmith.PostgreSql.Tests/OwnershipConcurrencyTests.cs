using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Blacksmith.Domain.Entities;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace Blacksmith.PostgreSql.Tests;

public sealed class OwnershipConcurrencyTests : PostgreSqlTestDatabase
{
    [PostgreSqlFact]
    public async Task Concurrent_insert_after_empty_check_returns_409_and_preserves_design_and_resource()
    {
        var owner = await SeedDesign();
        var gate = SaveGate.DesignDelete();
        using var factory = new PostgreSqlApiFactory(ConnectionString, gate);
        using var client = CreateClient(factory);
        var deleting = client.DeleteAsync($"/designs/{owner}");
        try
        {
            await gate.Entered.Task.WaitAsync(TimeSpan.FromSeconds(15));
            // Independent connection commits after the deletion snapshot was read.
            await using var competitor = CreateContext();
            competitor.Resources.Add(new ResourceEntity
            { Id = Guid.NewGuid(), DesignId = owner, Name = "Concurrent", Type = "generic" });
            await competitor.SaveChangesAsync();
        }
        finally { gate.Continue.TrySetResult(); }

        var response = await deleting;
        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
        Assert.Equal("Cannot delete this design: deployment history exists or its resources changed concurrently.",
            (await response.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("error").GetString());
        await using var verification = CreateContext();
        Assert.True(await verification.Designs.AnyAsync(x => x.Id == owner));
        Assert.Equal(owner, (await verification.Resources.SingleAsync()).DesignId);
        Assert.Equal(0, factory.Cloud.Calls);
    }

    [PostgreSqlFact]
    public async Task Concurrent_insert_rolls_back_deletion_of_existing_resources_and_configuration()
    {
        var owner = await SeedDesign();
        var existing = Guid.NewGuid();
        await using (var db = CreateContext()) {
            db.Resources.Add(new ResourceEntity { Id = existing, DesignId = owner, Name = "Saved", Type = "generic" });
            db.ResourceConfigurations.Add(new ResourceConfiguration { ResourceId = existing, SchemaVersion = 1, Configuration = "{}" });
            await db.SaveChangesAsync();
        }
        var gate = SaveGate.DesignDelete();
        using var factory = new PostgreSqlApiFactory(ConnectionString, gate);
        using var client = CreateClient(factory);
        var deleting = client.DeleteAsync($"/designs/{owner}");
        try {
            await gate.Entered.Task.WaitAsync(TimeSpan.FromSeconds(15));
            await using var competitor = CreateContext();
            competitor.Resources.Add(new ResourceEntity { Id = Guid.NewGuid(), DesignId = owner, Name = "Concurrent", Type = "generic", X = 1 });
            await competitor.SaveChangesAsync();
        } finally { gate.Continue.TrySetResult(); }
        Assert.Equal(HttpStatusCode.Conflict, (await deleting).StatusCode);
        await using var verification = CreateContext();
        Assert.True(await verification.Designs.AnyAsync(x => x.Id == owner));
        Assert.Equal(2, await verification.Resources.CountAsync());
        Assert.Equal(existing, (await verification.ResourceConfigurations.SingleAsync()).ResourceId);
        Assert.Equal(0, factory.Cloud.Calls);
    }

    [PostgreSqlFact]
    public async Task Deployment_inserted_after_snapshot_blocks_delete_and_preserves_configuration()
    {
        var owner = await SeedDesign();
        var resource = Guid.NewGuid();
        await using (var db = CreateContext()) {
            db.Resources.Add(new ResourceEntity { Id = resource, DesignId = owner, Name = "Saved", Type = "generic" });
            db.ResourceConfigurations.Add(new ResourceConfiguration { ResourceId = resource, SchemaVersion = 1, Configuration = "{}" });
            await db.SaveChangesAsync();
        }
        var gate = SaveGate.DesignDelete();
        using var factory = new PostgreSqlApiFactory(ConnectionString, gate);
        using var client = CreateClient(factory);
        var deleting = client.DeleteAsync($"/designs/{owner}");
        try {
            await gate.Entered.Task.WaitAsync(TimeSpan.FromSeconds(15));
            await using var competitor = CreateContext();
            competitor.StorageDeployments.Add(new StorageDeployment {
                Id = Guid.NewGuid(), ResourceId = resource, DesignId = owner, ResourceRevision = 1,
                Configuration = "{}", RequestHash = new string('a', 64), ConfigurationHash = new string('b', 64),
                OwnershipMarker = new string('c', 32), ProjectId = "example-project-123",
                BucketName = "blacksmith-fixture", Location = "europe-west9"
            });
            await competitor.SaveChangesAsync();
        } finally { gate.Continue.TrySetResult(); }
        Assert.Equal(HttpStatusCode.Conflict, (await deleting).StatusCode);
        await using var verification = CreateContext();
        Assert.True(await verification.Designs.AnyAsync(x => x.Id == owner));
        Assert.Single(await verification.Resources.ToListAsync());
        Assert.Single(await verification.ResourceConfigurations.ToListAsync());
        Assert.Single(await verification.StorageDeployments.ToListAsync());
        Assert.Equal(0, factory.Cloud.Calls);
    }

    [PostgreSqlFact]
    public async Task Undeployed_design_deletion_removes_jsonb_configuration_atomically()
    {
        var owner = await SeedDesign();
        var resource = Guid.NewGuid();
        await using (var db = CreateContext()) {
            db.Resources.Add(new ResourceEntity { Id = resource, DesignId = owner, Name = "Saved", Type = "generic" });
            db.ResourceConfigurations.Add(new ResourceConfiguration { ResourceId = resource, SchemaVersion = 1, Configuration = "{}" });
            await db.SaveChangesAsync();
        }
        using var factory = new PostgreSqlApiFactory(ConnectionString);
        using var client = CreateClient(factory);
        Assert.Equal(HttpStatusCode.NoContent, (await client.DeleteAsync($"/designs/{owner}")).StatusCode);
        await using var verification = CreateContext();
        Assert.False(await verification.Designs.AnyAsync(x => x.Id == owner));
        Assert.Empty(await verification.Resources.ToListAsync());
        Assert.Empty(await verification.ResourceConfigurations.ToListAsync());
        Assert.Equal(6, await verification.ResourceTypes.CountAsync());
        Assert.Equal(0, factory.Cloud.Calls);
    }

    [PostgreSqlFact]
    public async Task Concurrent_parent_delete_after_existence_check_returns_404_and_creates_no_orphan()
    {
        var owner = await SeedDesign();
        var gate = SaveGate.ResourceCreate();
        using var factory = new PostgreSqlApiFactory(ConnectionString, gate);
        using var client = CreateClient(factory);
        var creating = client.PostAsJsonAsync("/resources", new { designId = owner, name = "Concurrent", type = "generic" });
        try
        {
            await gate.Entered.Task.WaitAsync(TimeSpan.FromSeconds(15));
            await using var competitor = CreateContext();
            await competitor.Database.ExecuteSqlInterpolatedAsync($"DELETE FROM designs WHERE \"Id\" = {owner}");
        }
        finally { gate.Continue.TrySetResult(); }

        var response = await creating;
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
        Assert.Equal("Design not found.",
            (await response.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("error").GetString());
        await using var verification = CreateContext();
        Assert.False(await verification.Designs.AnyAsync(x => x.Id == owner));
        Assert.Empty(await verification.Resources.ToListAsync());
        Assert.Equal(0, factory.Cloud.Calls);
    }

    [PostgreSqlFact]
    public async Task Parallel_legacy_creates_recreate_one_stable_owner_without_duplicate_or_orphan()
    {
        await using (var db = CreateContext())
        {
            await db.Database.MigrateAsync();
            await db.Database.ExecuteSqlInterpolatedAsync($"DELETE FROM designs WHERE \"Id\" = {LegacyDesign.Id}");
        }
        using var factory = new PostgreSqlApiFactory(ConnectionString);
        using var client = CreateClient(factory);
        var responses = await Task.WhenAll(Enumerable.Range(0, 8).Select(index => client.PostAsJsonAsync(
            "/resources", new { name = $"Legacy {index}", type = "generic", x = index })));
        Assert.All(responses, response => Assert.Equal(HttpStatusCode.Created, response.StatusCode));
        await using var verification = CreateContext();
        Assert.Equal(LegacyDesign.Id, (await verification.Designs.SingleAsync()).Id);
        var resources = await verification.Resources.ToListAsync();
        Assert.Equal(8, resources.Count);
        Assert.All(resources, resource => Assert.Equal(LegacyDesign.Id, resource.DesignId));
        Assert.Equal(0, factory.Cloud.Calls);
        foreach (var response in responses) response.Dispose();
    }

    [PostgreSqlFact]
    public async Task PostgreSql_http_crud_supports_ownership_reassignment_and_undeployed_delete()
    {
        var first = await SeedDesign();
        using var factory = new PostgreSqlApiFactory(ConnectionString);
        using var client = CreateClient(factory);
        var secondResponse = await client.PostAsJsonAsync("/designs", new { name = "Second", description = "Details" });
        Assert.Equal(HttpStatusCode.Created, secondResponse.StatusCode);
        var second = (await secondResponse.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetGuid();
        var created = await client.PostAsJsonAsync("/resources", new { designId = first, name = "Resource", type = "generic", x = -4, y = 7 });
        Assert.Equal(HttpStatusCode.Created, created.StatusCode);
        var resource = await created.Content.ReadFromJsonAsync<JsonElement>();
        var id = resource.GetProperty("id").GetGuid();
        var persisted = await client.GetFromJsonAsync<JsonElement>($"/resources/{id}");
        // PostgreSQL timestamps have microsecond precision; .NET DateTime ticks are 100 ns.
        var postedTime = resource.GetProperty("createdAtUtc").GetDateTime();
        Assert.Equal(new DateTime(postedTime.Ticks - postedTime.Ticks % 10, DateTimeKind.Utc),
            persisted.GetProperty("createdAtUtc").GetDateTime());
        Assert.Equal(HttpStatusCode.OK, (await client.PutAsJsonAsync($"/designs/{second}", new { name = "Renamed" })).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await client.PutAsJsonAsync($"/resources/{id}",
            new { designId = second, name = "Moved", type = "generic", x = 2, y = -8 })).StatusCode);
        var moved = Assert.Single((await client.GetFromJsonAsync<JsonElement>($"/designs/{second}/resources")).EnumerateArray());
        Assert.Equal(second, moved.GetProperty("designId").GetGuid());
        Assert.Equal(persisted.GetProperty("createdAtUtc").GetDateTime(), moved.GetProperty("createdAtUtc").GetDateTime());
        Assert.Equal(HttpStatusCode.NoContent, (await client.DeleteAsync($"/designs/{first}")).StatusCode);
        Assert.Equal(HttpStatusCode.NoContent, (await client.DeleteAsync($"/designs/{second}")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await client.GetAsync($"/designs/{second}")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await client.GetAsync($"/resources/{id}")).StatusCode);
        Assert.Equal(0, factory.Cloud.Calls);
    }

    private async Task<Guid> SeedDesign()
    {
        await using var db = CreateContext();
        await db.Database.MigrateAsync();
        var design = new DesignEntity { Id = Guid.NewGuid(), Name = "Owner" };
        db.Designs.Add(design);
        await db.SaveChangesAsync();
        return design.Id;
    }

    private static HttpClient CreateClient(PostgreSqlApiFactory factory) => factory.CreateClient(
        new WebApplicationFactoryClientOptions { BaseAddress = new Uri("https://localhost"), AllowAutoRedirect = false });
}
