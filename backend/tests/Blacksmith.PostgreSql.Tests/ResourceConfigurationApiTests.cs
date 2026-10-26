using System.Net;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using Blacksmith.Domain.Entities;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace Blacksmith.PostgreSql.Tests;

public sealed class ResourceConfigurationApiTests : PostgreSqlTestDatabase
{
    private const string Valid = """{"schemaVersion":1,"configuration":{"projectId":"example-project-123","bucketName":"blacksmith-example-assets","location":"europe-west9"}}""";

    [PostgreSqlFact]
    public async Task Two_configured_resources_round_trip_and_replace_native_jsonb_without_metadata_changes()
    {
        var ids = await Seed(2);
        var before = await ResourceRows();
        using var factory = new PostgreSqlApiFactory(ConnectionString);
        using var client = Client(factory);
        Assert.Equal(HttpStatusCode.OK, (await Put(client, ids[0], Valid)).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await Put(client, ids[1], Valid.Replace("example-assets", "second-assets"))).StatusCode);
        var sibling = await client.GetStringAsync($"/resources/{ids[1]}/configuration");
        var replace = await Put(client, ids[0], Valid.Replace("europe-west9", "us-central1"));
        Assert.Equal(HttpStatusCode.OK, replace.StatusCode);
        Assert.Equal(await replace.Content.ReadAsStringAsync(), await client.GetStringAsync($"/resources/{ids[0]}/configuration"));
        Assert.Equal(sibling, await client.GetStringAsync($"/resources/{ids[1]}/configuration"));
        Assert.Equal(before, await ResourceRows());
        Assert.Equal("jsonb", await Scalar<string>("SELECT pg_typeof(configuration)::text FROM resource_configurations LIMIT 1"));
        Assert.Equal("object", await Scalar<string>("SELECT jsonb_typeof(configuration) FROM resource_configurations LIMIT 1"));
        Assert.Equal(2L, await Scalar<long>("SELECT count(*) FROM resource_configurations"));
        Assert.Equal("us-central1", await Scalar<string>($"SELECT configuration->>'location' FROM resource_configurations WHERE resource_id='{ids[0]}'"));
        Assert.Equal(0L, await Scalar<long>("SELECT count(*) FROM resource_configurations WHERE configuration ? 'schemaVersion' OR configuration ? 'softDeleteRetentionDays'"));
        using var metadata = JsonDocument.Parse(await client.GetStringAsync($"/resources/{ids[0]}"));
        Assert.Equal(new[] { "createdAtUtc", "id", "name", "type", "x", "y" }, metadata.RootElement.EnumerateObject().Select(x => x.Name).Order());
        using var scoped = JsonDocument.Parse(await client.GetStringAsync($"/designs/{LegacyDesign.Id}/resources"));
        Assert.Equal(2, scoped.RootElement.GetArrayLength());
        Assert.Equal(new[] { "createdAtUtc", "designId", "id", "name", "type", "x", "y" }, scoped.RootElement[0].EnumerateObject().Select(x => x.Name).Order());
        Assert.Equal(0, factory.Cloud.Calls);
    }

    [PostgreSqlFact]
    public async Task Rejected_configuration_and_metadata_writes_leave_previous_state_intact_and_release_locks()
    {
        var id = (await Seed())[0];
        using var factory = new PostgreSqlApiFactory(ConnectionString);
        using var client = Client(factory);
        Assert.Equal(HttpStatusCode.OK, (await Put(client, id, Valid)).StatusCode);
        var rows = await ResourceRows();
        var document = await Scalar<string>("SELECT configuration::text FROM resource_configurations");
        foreach (var invalid in new[] { Valid.Replace("\"schemaVersion\":1", "\"schemaVersion\":2"), Valid.Replace("europe-west9", "US"), Valid.Replace("\"location\":", "\"private_key\":\"DO_NOT_ECHO_FIXTURE\",\"location\":") })
            Assert.Equal(HttpStatusCode.BadRequest, (await Put(client, id, invalid)).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await client.PutAsJsonAsync($"/resources/{id}", new { name = "Invalid conversion", type = "gcp.compute.instance", x = 0, y = 0 })).StatusCode);
        Assert.Equal(rows, await ResourceRows());
        Assert.Equal(document, await Scalar<string>("SELECT configuration::text FROM resource_configurations"));
        // A subsequent accepted update proves rejected transactional operations do not retain a parent lock.
        Assert.Equal(HttpStatusCode.OK, (await Put(client, id, Valid.Replace("example-assets", "updated-assets"))).StatusCode);
        Assert.Equal(1L, await Scalar<long>("SELECT count(*) FROM resource_configurations"));
        Assert.Equal(0, factory.Cloud.Calls);
    }

    [PostgreSqlFact]
    public async Task Metadata_only_update_preserves_document_and_resource_delete_cascades_only_its_child()
    {
        var ids = await Seed(2);
        using var factory = new PostgreSqlApiFactory(ConnectionString);
        using var client = Client(factory);
        foreach (var id in ids) Assert.Equal(HttpStatusCode.OK, (await Put(client, id, Valid)).StatusCode);
        var saved = await client.GetStringAsync($"/resources/{ids[0]}/configuration");
        Assert.Equal(HttpStatusCode.OK, (await client.PutAsJsonAsync($"/resources/{ids[0]}", new { name = "Renamed", type = "gcp.storage.bucket", x = 4, y = 5 })).StatusCode);
        Assert.Equal(saved, await client.GetStringAsync($"/resources/{ids[0]}/configuration"));
        Assert.Equal(HttpStatusCode.Conflict, (await client.DeleteAsync($"/designs/{LegacyDesign.Id}")).StatusCode);
        Assert.Equal(HttpStatusCode.NoContent, (await client.DeleteAsync($"/resources/{ids[0]}")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await client.GetAsync($"/resources/{ids[0]}/configuration")).StatusCode);
        await using var db = CreateContext();
        Assert.Equal(ids[1], (await db.ResourceConfigurations.SingleAsync()).ResourceId);
        Assert.Equal(ids[1], (await db.Resources.SingleAsync()).Id);
        Assert.Equal(0, factory.Cloud.Calls);
    }

    [PostgreSqlFact]
    public async Task Overlapping_first_puts_replace_one_row_with_last_successful_write()
    {
        var id = (await Seed())[0];
        var gate = new SaveGate(db => db.ChangeTracker.Entries<ResourceConfiguration>().Any(x => x.State == EntityState.Added));
        using var factory = new PostgreSqlApiFactory(ConnectionString, gate);
        using var client = Client(factory);
        var first = Put(client, id, Valid);
        Task<HttpResponseMessage> second;
        try
        {
            await gate.Entered.Task.WaitAsync(TimeSpan.FromSeconds(15));
            second = Put(client, id, Valid.Replace("example-assets", "second-assets"));
            await WaitForCompetingWrite();
        }
        finally { gate.Continue.TrySetResult(); }
        Assert.Equal(HttpStatusCode.OK, (await first).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await second).StatusCode);
        Assert.Equal(1L, await Scalar<long>("SELECT count(*) FROM resource_configurations"));
        Assert.Equal("blacksmith-second-assets", await Scalar<string>("SELECT configuration->>'bucketName' FROM resource_configurations"));
        Assert.Equal(0, factory.Cloud.Calls);
    }

    [PostgreSqlFact]
    public async Task Configuration_write_before_type_change_keeps_compatible_resource()
        => await TypeRace(configurationFirst: true);

    [PostgreSqlFact]
    public async Task Type_change_before_configuration_write_rejects_incompatible_configuration()
        => await TypeRace(configurationFirst: false);

    private async Task TypeRace(bool configurationFirst)
    {
        var id = (await Seed())[0];
        var gate = new SaveGate(db => configurationFirst
            ? db.ChangeTracker.Entries<ResourceConfiguration>().Any(x => x.State == EntityState.Added)
            : db.ChangeTracker.Entries<ResourceEntity>().Any(x => x.State == EntityState.Modified));
        using var factory = new PostgreSqlApiFactory(ConnectionString, gate);
        using var client = Client(factory);
        Task<HttpResponseMessage> Configuration() => Put(client, id, Valid);
        Task<HttpResponseMessage> Type() => client.PutAsJsonAsync($"/resources/{id}", new { name = "Changed type", type = "gcp.compute.instance", x = 3, y = 2 });
        var first = configurationFirst ? Configuration() : Type();
        Task<HttpResponseMessage> second;
        try
        {
            await gate.Entered.Task.WaitAsync(TimeSpan.FromSeconds(15));
            second = configurationFirst ? Type() : Configuration();
            await WaitForCompetingWrite();
        }
        finally { gate.Continue.TrySetResult(); }
        Assert.Equal(HttpStatusCode.OK, (await first).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await second).StatusCode);
        await using var db = CreateContext();
        Assert.Equal(configurationFirst ? "gcp.storage.bucket" : "gcp.compute.instance", (await db.Resources.SingleAsync()).Type);
        Assert.Equal(configurationFirst ? 1 : 0, await db.ResourceConfigurations.CountAsync());
        Assert.Equal(0, factory.Cloud.Calls);
    }

    private async Task WaitForCompetingWrite()
    {
        var deadline = DateTime.UtcNow.AddSeconds(15);
        while (DateTime.UtcNow < deadline)
        {
            if (await Scalar<long>("SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND wait_event_type='Lock'") > 0)
                return;
            await Task.Delay(25);
        }
        throw new InvalidOperationException("The competing write did not reach the expected PostgreSQL lock wait.");
    }

    private async Task<Guid[]> Seed(int count = 1)
    {
        await using var db = CreateContext();
        await db.Database.MigrateAsync();
        var storage = await db.ResourceTypes.SingleAsync(x => x.Code == "storage");
        var resources = Enumerable.Range(0, count).Select(i => new ResourceEntity
        { Id = Guid.NewGuid(), DesignId = LegacyDesign.Id, ResourceTypeId = storage.Id, Name = "Fixture " + i, Type = "gcp.storage.bucket", X = i, Y = 2 }).ToArray();
        db.Resources.AddRange(resources);
        await db.SaveChangesAsync();
        return resources.Select(x => x.Id).ToArray();
    }

    private Task<string> ResourceRows() => Scalar<string>("SELECT jsonb_agg(to_jsonb(r) ORDER BY \"Id\")::text FROM resources r");
    private static HttpClient Client(PostgreSqlApiFactory factory) => factory.CreateClient(new WebApplicationFactoryClientOptions { BaseAddress = new Uri("https://localhost") });
    private static Task<HttpResponseMessage> Put(HttpClient client, Guid id, string json) =>
        client.PutAsync($"/resources/{id}/configuration", new StringContent(json, Encoding.UTF8, "application/json"));
}
