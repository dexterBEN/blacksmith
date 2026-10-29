using System.Net;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using Blacksmith.Domain.Entities;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace Blacksmith.PostgreSql.Tests;

public sealed class ConfiguredResourceTests : PostgreSqlTestDatabase
{
    private const string Configuration = """{"schemaVersion":1,"configuration":{"projectId":"example-project-123","bucketName":"blacksmith-example-assets","location":"europe-west9"}}""";
    private static string Body(int x = 3, int y = 2, string bucket = "blacksmith-example-assets") =>
        $$"""{"name":"Cloud Storage display label","type":"gcp.storage.bucket","resourceTypeId":"10000000-0000-0000-0000-000000000002","x":{{x}},"y":{{y}},"configuration":{{Configuration.Replace("blacksmith-example-assets", bucket)}}} """;

    [PostgreSqlFact]
    public async Task Two_resources_round_trip_update_independently_and_recover_by_original_id()
    {
        await Seed();
        using var factory = new PostgreSqlApiFactory(ConnectionString);
        using var client = Client(factory);
        var a = Guid.NewGuid(); var b = Guid.NewGuid();
        // Intentionally discard the first successful response, as if it was lost.
        var created = await Write(client, a, Body());
        Assert.Equal(HttpStatusCode.Created, created.StatusCode);
        Assert.Equal(HttpStatusCode.Created, (await Write(client, b, Body(-42, 500, "blacksmith-second-assets"))).StatusCode);
        var read = await client.GetAsync($"/resources/{a}?include=configuration");
        Assert.Equal(await created.Content.ReadAsStringAsync(), await read.Content.ReadAsStringAsync());
        var recovered = await read.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal(a, recovered.GetProperty("id").GetGuid());
        Assert.Equal(LegacyDesign.Id, recovered.GetProperty("designId").GetGuid());
        Assert.Equal(1L, recovered.GetProperty("revision").GetInt64());
        Assert.Equal("blacksmith-example-assets", recovered.GetProperty("configuration").GetProperty("configuration").GetProperty("bucketName").GetString());
        var sibling = await client.GetStringAsync($"/resources/{b}?include=configuration");
        var tag = read.Headers.ETag!.Tag;
        var noop = await Write(client, a, Body(), tag);
        Assert.Equal("unchanged", noop.Headers.GetValues("X-Resource-Write-Outcome").Single());
        Assert.Equal(1L, (await noop.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("revision").GetInt64());
        Assert.Equal(HttpStatusCode.OK, (await Write(client, a, Body(bucket: "blacksmith-edited-assets"), tag)).StatusCode);
        Assert.Equal(sibling, await client.GetStringAsync($"/resources/{b}?include=configuration"));
        Assert.Equal(2L, await Scalar<long>($"SELECT revision FROM resources WHERE \"Id\"='{a}'"));
        Assert.Equal(2L, await Scalar<long>("SELECT count(*) FROM resources"));
        Assert.Equal("jsonb", await Scalar<string>("SELECT pg_typeof(configuration)::text FROM resource_configurations LIMIT 1"));
        Assert.Equal("object", await Scalar<string>("SELECT jsonb_typeof(configuration) FROM resource_configurations LIMIT 1"));
        var scoped = await client.GetFromJsonAsync<JsonElement>($"/designs/{LegacyDesign.Id}/resources?include=configuration");
        Assert.Equal(new[] { a, b }, scoped.EnumerateArray().Select(x => x.GetProperty("id").GetGuid()));
        Assert.Equal(0, factory.Cloud.Calls);
    }

    [PostgreSqlFact]
    public async Task Invalid_config_and_database_write_failure_leave_no_partial_parent_or_configuration()
    {
        await Seed();
        using var factory = new PostgreSqlApiFactory(ConnectionString);
        using var client = Client(factory);
        Assert.Equal(HttpStatusCode.BadRequest, (await Write(client, Guid.NewGuid(), Body().Replace("europe-west9", "US"))).StatusCode);
        Assert.Equal(0L, await Scalar<long>("SELECT count(*) FROM resources"));
        // Force a child INSERT failure after validation, exclusively in this disposable database.
        await using (var db = CreateContext()) await db.Database.ExecuteSqlRawAsync(
            "ALTER TABLE resource_configurations ADD CONSTRAINT fixture_reject_insert CHECK (schema_version <> 1)");
        await Assert.ThrowsAsync<DbUpdateException>(() => Write(client, Guid.NewGuid(), Body()));
        Assert.Equal(0L, await Scalar<long>("SELECT count(*) FROM resources"));
        Assert.Equal(0L, await Scalar<long>("SELECT count(*) FROM resource_configurations"));
        Assert.Equal(0, factory.Cloud.Calls);
    }

    [PostgreSqlFact]
    public async Task Failed_child_update_rolls_back_metadata_configuration_and_revision_together()
    {
        await Seed();
        using var factory = new PostgreSqlApiFactory(ConnectionString);
        using var client = Client(factory);
        var id = Guid.NewGuid();
        await Write(client, id, Body());
        var read = await client.GetAsync($"/resources/{id}?include=configuration");
        var before = await read.Content.ReadAsStringAsync();
        await using (var db = CreateContext()) await db.Database.ExecuteSqlRawAsync(
            "ALTER TABLE resource_configurations ADD CONSTRAINT fixture_reject_update CHECK (configuration->>'bucketName' <> 'rejected-bucket')");
        await Assert.ThrowsAsync<DbUpdateException>(() => Write(client, id,
            Body(40, 500, "rejected-bucket").Replace("display label", "changed label"), read.Headers.ETag!.Tag));
        Assert.Equal(before, await client.GetStringAsync($"/resources/{id}?include=configuration"));
        Assert.Equal(0, factory.Cloud.Calls);
    }

    [PostgreSqlFact]
    public async Task Same_id_replay_and_stale_edit_are_precondition_failures_without_overwrite()
    {
        await Seed();
        using var factory = new PostgreSqlApiFactory(ConnectionString);
        using var client = Client(factory);
        var id = Guid.NewGuid();
        Assert.Equal(HttpStatusCode.Created, (await Write(client, id, Body())).StatusCode);
        var before = await client.GetStringAsync($"/resources/{id}?include=configuration");
        await Code(await Write(client, id, Body(bucket: "different-intent")), HttpStatusCode.PreconditionFailed, "resource_exists");
        var tag = (await client.GetAsync($"/resources/{id}?include=configuration")).Headers.ETag!.Tag;
        Assert.Equal(HttpStatusCode.OK, (await Write(client, id, Body(bucket: "newer-value"), tag)).StatusCode);
        var newer = await client.GetStringAsync($"/resources/{id}?include=configuration");
        Assert.NotEqual(before, newer);
        await Code(await Write(client, id, Body(), tag), HttpStatusCode.PreconditionFailed, "revision_conflict");
        Assert.Equal(newer, await client.GetStringAsync($"/resources/{id}?include=configuration"));
        Assert.Equal(0, factory.Cloud.Calls);
    }

    [PostgreSqlFact]
    public async Task Parallel_distinct_ids_contend_for_one_tile_and_leave_only_one_complete_aggregate()
        => await Contention(sameId: false);

    [PostgreSqlFact]
    public async Task Parallel_same_id_create_has_one_winner_and_one_precondition_failure()
        => await Contention(sameId: true);

    private async Task Contention(bool sameId)
    {
        await Seed();
        var gate = SaveGate.ResourceCreate();
        using var factory = new PostgreSqlApiFactory(ConnectionString, gate);
        using var client = Client(factory);
        var a = Guid.NewGuid(); var b = sameId ? a : Guid.NewGuid();
        var first = Write(client, a, Body());
        HttpResponseMessage second;
        try
        {
            await gate.Entered.Task.WaitAsync(TimeSpan.FromSeconds(15));
            second = await Write(client, b, Body());
        }
        finally { gate.Continue.TrySetResult(); }
        Assert.Equal(HttpStatusCode.Created, second.StatusCode);
        await Code(await first, sameId ? HttpStatusCode.PreconditionFailed : HttpStatusCode.Conflict, sameId ? "resource_exists" : "tile_occupied");
        Assert.Equal(1L, await Scalar<long>("SELECT count(*) FROM resources"));
        Assert.Equal(1L, await Scalar<long>("SELECT count(*) FROM resource_configurations"));
        Assert.Equal(0, factory.Cloud.Calls);
    }

    [PostgreSqlFact]
    public async Task Concurrent_edits_with_same_revision_have_only_one_winner()
    {
        await Seed();
        var id = Guid.NewGuid();
        var gate = new SaveGate(db => db.ChangeTracker.Entries<ResourceEntity>().Any(x => x.State == EntityState.Modified));
        using var factory = new PostgreSqlApiFactory(ConnectionString, gate);
        using var client = Client(factory);
        await Write(client, id, Body());
        var tag = (await client.GetAsync($"/resources/{id}?include=configuration")).Headers.ETag!.Tag;
        var first = Write(client, id, Body(bucket: "first-edit"), tag);
        Task<HttpResponseMessage> second;
        try
        {
            await gate.Entered.Task.WaitAsync(TimeSpan.FromSeconds(15));
            second = Write(client, id, Body(bucket: "second-edit"), tag);
            var deadline = DateTime.UtcNow.AddSeconds(15);
            while (await Scalar<long>("SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND wait_event_type='Lock'") == 0)
            {
                if (DateTime.UtcNow > deadline) throw new InvalidOperationException("Competing edit did not wait for the Resource lock.");
                await Task.Delay(25);
            }
        }
        finally { gate.Continue.TrySetResult(); }
        Assert.Equal(HttpStatusCode.OK, (await first).StatusCode);
        await Code(await second, HttpStatusCode.PreconditionFailed, "revision_conflict");
        Assert.Equal("first-edit", await Scalar<string>("SELECT configuration->>'bucketName' FROM resource_configurations"));
        Assert.Equal(2L, await Scalar<long>("SELECT revision FROM resources"));
        Assert.Equal(0, factory.Cloud.Calls);
    }

    [PostgreSqlFact]
    public async Task Legacy_post_put_and_owner_changes_cannot_bypass_tile_uniqueness()
    {
        var other = await Seed();
        using var factory = new PostgreSqlApiFactory(ConnectionString);
        using var client = Client(factory);
        var a = Guid.NewGuid(); var b = Guid.NewGuid();
        await Write(client, a, Body());
        await Write(client, b, Body(4, 5));
        var before = await client.GetStringAsync($"/resources/{b}?include=configuration");
        await Code(await client.PostAsJsonAsync("/resources", new { name = "Legacy duplicate", type = "generic", designId = LegacyDesign.Id, x = 3, y = 2 }), HttpStatusCode.Conflict, "tile_occupied");
        await Code(await client.PutAsJsonAsync($"/resources/{b}", new { name = "Move", type = "gcp.storage.bucket", x = 3, y = 2 }), HttpStatusCode.Conflict, "tile_occupied");
        Assert.Equal(before, await client.GetStringAsync($"/resources/{b}?include=configuration"));
        Assert.Equal(HttpStatusCode.Created, (await client.PostAsJsonAsync("/resources", new { name = "Other owner", type = "generic", designId = other, x = 3, y = 2 })).StatusCode);
        await Code(await client.PutAsJsonAsync($"/resources/{a}", new { name = "Wrong owner move", type = "gcp.storage.bucket", designId = other, x = 3, y = 2 }), HttpStatusCode.Conflict, "tile_occupied");
        Assert.Equal(3L, await Scalar<long>("SELECT count(*) FROM resources"));
        Assert.Equal(2L, await Scalar<long>("SELECT count(*) FROM resource_configurations"));
        Assert.Equal(0, factory.Cloud.Calls);
    }

    [PostgreSqlFact]
    public async Task Legacy_metadata_and_configuration_writes_advance_revision_and_preserve_other_content()
    {
        await Seed();
        using var factory = new PostgreSqlApiFactory(ConnectionString);
        using var client = Client(factory);
        var id = Guid.NewGuid();
        await Write(client, id, Body());
        var configuration = await Scalar<string>("SELECT configuration::text FROM resource_configurations");
        var tag = (await client.GetAsync($"/resources/{id}?include=configuration")).Headers.ETag!.Tag;
        Assert.Equal(HttpStatusCode.OK, (await client.PutAsJsonAsync($"/resources/{id}", new { name = "Metadata label", type = "gcp.storage.bucket", x = 30, y = -12 })).StatusCode);
        Assert.Equal(2L, await Scalar<long>("SELECT revision FROM resources"));
        Assert.Equal(configuration, await Scalar<string>("SELECT configuration::text FROM resource_configurations"));
        await Code(await Write(client, id, Body(), tag), HttpStatusCode.PreconditionFailed, "revision_conflict");
        Assert.Equal(HttpStatusCode.OK, (await client.PutAsync($"/resources/{id}/configuration", new StringContent(Configuration.Replace("example-assets", "legacy-config-edit"), Encoding.UTF8, "application/json"))).StatusCode);
        Assert.Equal(3L, await Scalar<long>("SELECT revision FROM resources"));
        Assert.Equal("Metadata label", await Scalar<string>("SELECT \"Name\" FROM resources"));
        Assert.Equal(0, factory.Cloud.Calls);
    }

    [PostgreSqlFact]
    public async Task Wrong_design_missing_entities_catalog_and_incompatible_type_do_not_mutate()
    {
        var other = await Seed();
        using var factory = new PostgreSqlApiFactory(ConnectionString);
        using var client = Client(factory);
        var id = Guid.NewGuid();
        await Write(client, id, Body());
        await Code(await Write(client, id, Body(), Tag(id, 1), other), HttpStatusCode.Conflict, "resource_design_mismatch");
        var unknown = Guid.NewGuid();
        await Code(await Write(client, unknown, Body(), Tag(unknown, 1)), HttpStatusCode.NotFound, "resource_not_found");
        await Code(await Write(client, unknown, Body(), design: Guid.NewGuid()), HttpStatusCode.NotFound, "design_not_found");
        Assert.Equal(HttpStatusCode.BadRequest, (await Write(client, unknown, Body().Replace("000000000002", "000000000001"))).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await Write(client, id, Body().Replace("gcp.storage.bucket", "gcp.compute.instance"), Tag(id, 1))).StatusCode);
        Assert.Equal(1L, await Scalar<long>("SELECT revision FROM resources"));
        Assert.Equal(1L, await Scalar<long>("SELECT count(*) FROM resources"));
        var incompatible = await client.PostAsJsonAsync("/resources", new { name = "Persisted compute", type = "gcp.compute.instance", x = 7, y = 8 });
        var incompatibleId = (await incompatible.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetGuid();
        Assert.Equal(HttpStatusCode.BadRequest, (await Write(client, incompatibleId, Body(7, 8), Tag(incompatibleId, 1))).StatusCode);
        Assert.Equal(1L, await Scalar<long>("SELECT count(*) FROM resource_configurations"));
        Assert.Equal(0, factory.Cloud.Calls);
    }

    [PostgreSqlFact]
    public async Task Aggregate_reads_preserve_absent_and_hide_unsupported_historical_documents()
    {
        await Seed();
        using var factory = new PostgreSqlApiFactory(ConnectionString);
        using var client = Client(factory);
        var created = await client.PostAsJsonAsync("/resources", new { name = "Legacy", type = "gcp.storage.bucket", x = -8, y = 900 });
        var id = (await created.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetGuid();
        var absent = await client.GetFromJsonAsync<JsonElement>($"/resources/{id}?include=configuration");
        Assert.Equal("absent", absent.GetProperty("configurationState").GetString());
        Assert.Equal(JsonValueKind.Null, absent.GetProperty("configuration").ValueKind);
        await using (var db = CreateContext())
        {
            db.ResourceConfigurations.Add(new ResourceConfiguration { ResourceId = id, SchemaVersion = 999, Configuration = """{"private_key":"DO_NOT_ECHO_FIXTURE"}""" });
            await db.SaveChangesAsync();
        }
        var hidden = await client.GetStringAsync($"/resources/{id}?include=configuration");
        Assert.DoesNotContain("DO_NOT_ECHO_FIXTURE", hidden);
        Assert.Contains("unsupported", hidden);
        Assert.Equal(HttpStatusCode.Conflict, (await client.GetAsync($"/resources/{id}/configuration")).StatusCode);
        Assert.Equal(HttpStatusCode.NoContent, (await client.DeleteAsync($"/designs/{LegacyDesign.Id}")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await client.GetAsync($"/resources/{id}")).StatusCode);
        Assert.Equal(0L, await Scalar<long>("SELECT count(*) FROM resource_configurations"));
        Assert.Equal(0, factory.Cloud.Calls);
    }

    private async Task<Guid> Seed()
    {
        await using var db = CreateContext();
        await db.Database.MigrateAsync();
        Assert.False(db.Database.HasPendingModelChanges());
        var other = Guid.NewGuid();
        db.Designs.Add(new DesignEntity { Id = other, Name = "Other Design" });
        await db.SaveChangesAsync();
        return other;
    }

    [PostgreSqlFact]
    public async Task Parent_deleted_during_configured_create_returns_404_without_partial_aggregate()
    {
        var owner = await Seed();
        var gate = SaveGate.ResourceCreate();
        using var factory = new PostgreSqlApiFactory(ConnectionString, gate);
        using var client = Client(factory);
        var first = Write(client, Guid.NewGuid(), Body(), design: owner);
        try
        {
            await gate.Entered.Task.WaitAsync(TimeSpan.FromSeconds(15));
            await using var competitor = CreateContext();
            await competitor.Database.ExecuteSqlInterpolatedAsync($"DELETE FROM designs WHERE \"Id\"={owner}");
        }
        finally { gate.Continue.TrySetResult(); }
        await Code(await first, HttpStatusCode.NotFound, "design_not_found");
        Assert.Equal(0L, await Scalar<long>("SELECT count(*) FROM resources"));
        Assert.Equal(0L, await Scalar<long>("SELECT count(*) FROM resource_configurations"));
        Assert.Equal(0, factory.Cloud.Calls);
    }
    private static string Tag(Guid id, long revision) => $"\"resource-{id:N}-r{revision}\"";
    private static HttpClient Client(PostgreSqlApiFactory factory) => factory.CreateClient(new WebApplicationFactoryClientOptions { BaseAddress = new Uri("https://localhost") });
    private static Task<HttpResponseMessage> Write(HttpClient client, Guid id, string body, string? tag = null, Guid? design = null)
    {
        var request = new HttpRequestMessage(HttpMethod.Put, $"/designs/{design ?? LegacyDesign.Id}/resources/{id}")
            { Content = new StringContent(body, Encoding.UTF8, "application/json") };
        request.Headers.TryAddWithoutValidation(tag is null ? "If-None-Match" : "If-Match", tag ?? "*");
        return client.SendAsync(request);
    }
    private static async Task Code(HttpResponseMessage response, HttpStatusCode status, string code)
    {
        Assert.Equal(status, response.StatusCode);
        Assert.Equal(code, (await response.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("code").GetString());
    }
}
