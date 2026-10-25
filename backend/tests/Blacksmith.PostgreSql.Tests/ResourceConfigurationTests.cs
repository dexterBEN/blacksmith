using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Nodes;
using Blacksmith.Domain.Entities;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql;
using Xunit;

namespace Blacksmith.PostgreSql.Tests;

public sealed class ResourceConfigurationTests : PostgreSqlTestDatabase
{
    private const string PreviousMigration = "20261019094942_AddResourceTypeCatalog";
    private const string Original = """{"projectId":"example-project","nested":{"enabled":true,"value":null,"amount":12.5,"label":"é"},"items":[1,false,null,{"order":[3,2,1]}]}""";

    [PostgreSqlFact]
    public async Task Optional_relationship_uses_native_jsonb_required_fields_and_cascade()
    {
        await using var db = CreateContext();
        await db.Database.MigrateAsync();
        var resource = Resource();
        db.Resources.Add(resource);
        await db.SaveChangesAsync();
        db.ChangeTracker.Clear();
        Assert.Null((await db.Resources.Include(x => x.Configuration).SingleAsync()).Configuration);
        Assert.Empty(await db.ResourceConfigurations.ToArrayAsync());
        Assert.Equal("jsonb", await Scalar<string>("SELECT udt_name FROM information_schema.columns WHERE table_name='resource_configurations' AND column_name='configuration'"));
        Assert.Equal(0L, await Scalar<long>("SELECT count(*) FROM information_schema.columns WHERE table_name='resource_configurations' AND is_nullable='YES'"));
        Assert.Equal("CASCADE", await Scalar<string>("SELECT delete_rule FROM information_schema.referential_constraints WHERE constraint_name='FK_resource_configurations_resources_resource_id'"));
        Assert.Equal("RESTRICT", await Scalar<string>("SELECT delete_rule FROM information_schema.referential_constraints WHERE constraint_name='FK_resources_designs_design_id'"));
        Assert.False(db.Database.HasPendingModelChanges());
    }

    [PostgreSqlFact]
    public async Task Two_resources_in_one_design_round_trip_nested_json_and_track_document_replacement()
    {
        var first = Resource();
        var second = Resource(); // Even historical duplicate tile positions remain allowed in this issue.
        var firstId = first.Id;
        var secondId = second.Id;
        await using (var db = CreateContext())
        {
            await db.Database.MigrateAsync();
            first.Configuration = Configuration(firstId, Original);
            second.Configuration = Configuration(secondId, """{"other":["untouched",true]}""", 2);
            db.Resources.AddRange(first, second);
            await db.SaveChangesAsync();
        }
        var before = await OriginalRows();
        await using (var db = CreateContext())
        {
            var loaded = await db.Resources.Include(x => x.Configuration).SingleAsync(x => x.Id == firstId);
            var config = loaded.Configuration!;
            Assert.Equal(1, config.SchemaVersion);
            Assert.Equal(firstId, config.ResourceId);
            Assert.Same(loaded, config.Resource);
            AssertJson(Original, config.Configuration);
            Assert.Equal(0, await db.SaveChangesAsync());
            config.Configuration = """{"replacement":{"enabled":false},"values":[null,42,"new"]}""";
            config.SchemaVersion = 3;
            await db.SaveChangesAsync();
        }
        await using (var db = CreateContext())
        {
            var configs = await db.ResourceConfigurations.ToDictionaryAsync(x => x.ResourceId);
            Assert.Equal(2, configs.Count);
            Assert.Equal(3, configs[firstId].SchemaVersion);
            AssertJson("""{"replacement":{"enabled":false},"values":[null,42,"new"]}""", configs[firstId].Configuration);
            AssertJson("""{"other":["untouched",true]}""", configs[secondId].Configuration);
            Assert.Equal(2, configs[secondId].SchemaVersion);
        }
        Assert.Equal(before, await OriginalRows());
        Assert.Equal("object", await Scalar<string>($"SELECT jsonb_typeof(configuration) FROM resource_configurations WHERE resource_id='{firstId}'"));
        Assert.Equal("false", await Scalar<string>($"SELECT configuration->'replacement'->>'enabled' FROM resource_configurations WHERE resource_id='{firstId}'"));
    }

    [PostgreSqlFact]
    public async Task Jsonb_preserves_root_arrays_strings_numbers_booleans_and_json_null()
    {
        await using var db = CreateContext();
        await db.Database.MigrateAsync();
        var examples = new[] { """[1,{"nested":[true,null]}]""", "\"a JSON string\"", "12345678901234567890", "12.5", "true", "false", "null" };
        var rows = examples.Select(json =>
        {
            var resource = Resource();
            resource.Configuration = Configuration(resource.Id, json);
            return resource;
        }).ToArray();
        db.Resources.AddRange(rows);
        await db.SaveChangesAsync();
        db.ChangeTracker.Clear();
        var loaded = await db.ResourceConfigurations.ToDictionaryAsync(x => x.ResourceId);
        for (var i = 0; i < rows.Length; i++) AssertJson(examples[i], loaded[rows[i].Id].Configuration);
        Assert.Equal(0L, await Scalar<long>("SELECT count(*) FROM resource_configurations WHERE configuration IS NULL"));
        Assert.Equal(1L, await Scalar<long>("SELECT count(*) FROM resource_configurations WHERE jsonb_typeof(configuration)='null'"));
    }

    [PostgreSqlFact]
    public async Task PostgreSql_rejects_orphan_duplicate_invalid_version_invalid_json_and_sql_null()
    {
        await using var db = CreateContext();
        await db.Database.MigrateAsync();
        var resource = Resource();
        resource.Configuration = Configuration(resource.Id, Original);
        db.Resources.Add(resource);
        await db.SaveChangesAsync();
        var duplicate = await Assert.ThrowsAsync<PostgresException>(() => db.Database.ExecuteSqlInterpolatedAsync($"""
            INSERT INTO resource_configurations(resource_id,schema_version,configuration) VALUES ({resource.Id},1,'[]'::jsonb)
            """));
        Assert.Equal(PostgresErrorCodes.UniqueViolation, duplicate.SqlState);
        var orphan = await Assert.ThrowsAsync<PostgresException>(() => db.Database.ExecuteSqlInterpolatedAsync($"""
            INSERT INTO resource_configurations(resource_id,schema_version,configuration) VALUES ({Guid.NewGuid()},1,'[]'::jsonb)
            """));
        Assert.Equal(PostgresErrorCodes.ForeignKeyViolation, orphan.SqlState);
        foreach (var version in new[] { 0, -1 })
        {
            var invalid = await Assert.ThrowsAsync<PostgresException>(() => db.Database.ExecuteSqlInterpolatedAsync($"""
                UPDATE resource_configurations SET schema_version={version} WHERE resource_id={resource.Id}
                """));
            Assert.Equal(PostgresErrorCodes.CheckViolation, invalid.SqlState);
        }
        var sqlNull = await Assert.ThrowsAsync<PostgresException>(() => db.Database.ExecuteSqlInterpolatedAsync($"""
            UPDATE resource_configurations SET configuration=NULL WHERE resource_id={resource.Id}
            """));
        Assert.Equal(PostgresErrorCodes.NotNullViolation, sqlNull.SqlState);
        var malformed = await Assert.ThrowsAsync<PostgresException>(() => db.Database.ExecuteSqlInterpolatedAsync($"""
            UPDATE resource_configurations SET configuration='not JSON'::jsonb WHERE resource_id={resource.Id}
            """));
        Assert.Equal(PostgresErrorCodes.InvalidTextRepresentation, malformed.SqlState);
        db.ChangeTracker.Clear();
        AssertJson(Original, (await db.ResourceConfigurations.SingleAsync()).Configuration);
        Assert.Equal(1, (await db.ResourceConfigurations.SingleAsync()).SchemaVersion);
    }

    [PostgreSqlFact]
    public async Task Deleting_unloaded_resource_cascades_only_its_configuration_and_keeps_design_restrict()
    {
        var first = Resource();
        var second = Resource();
        await using (var db = CreateContext())
        {
            await db.Database.MigrateAsync();
            first.Configuration = Configuration(first.Id, Original);
            second.Configuration = Configuration(second.Id, "{}");
            db.Resources.AddRange(first, second);
            await db.SaveChangesAsync();
        }
        await using (var db = CreateContext())
        {
            var restrict = await Assert.ThrowsAsync<PostgresException>(() => db.Database.ExecuteSqlInterpolatedAsync(
                $"DELETE FROM designs WHERE \"Id\"={LegacyDesign.Id}"));
            Assert.Equal(PostgresErrorCodes.ForeignKeyViolation, restrict.SqlState);
            var unloaded = await db.Resources.SingleAsync(x => x.Id == first.Id);
            Assert.False(db.Entry(unloaded).Reference(x => x.Configuration).IsLoaded);
            db.Resources.Remove(unloaded);
            await db.SaveChangesAsync();
        }
        await using (var db = CreateContext())
        {
            Assert.Equal(second.Id, (await db.Resources.SingleAsync()).Id);
            Assert.Equal(second.Id, (await db.ResourceConfigurations.SingleAsync()).ResourceId);
            AssertJson("{}", (await db.ResourceConfigurations.SingleAsync()).Configuration);
            Assert.True(await db.Designs.AnyAsync(x => x.Id == LegacyDesign.Id));
        }
    }

    [PostgreSqlFact]
    public async Task Populated_migration_preserves_all_original_rows_and_downgrade_only_removes_configuration_table()
    {
        await using var db = CreateContext();
        var migrator = db.GetService<IMigrator>();
        await migrator.MigrateAsync(PreviousMigration);
        var design = new DesignEntity { Id = Guid.NewGuid(), Name = "Historical design é", Description = "Keep this metadata" };
        var first = Resource();
        first.DesignId = design.Id;
        first.ResourceTypeId = new Guid("10000000-0000-0000-0000-000000000002");
        first.Name = "  Historical bucket é  ";
        first.X = -37;
        first.Y = 9;
        var second = Resource();
        second.DesignId = design.Id;
        second.Type = "custom.legacy.type";
        second.X = first.X;
        second.Y = first.Y;
        db.Designs.Add(design);
        db.Resources.AddRange(first, second);
        await db.SaveChangesAsync();
        db.ChangeTracker.Clear();
        var before = await OriginalRows();
        await migrator.MigrateAsync();
        Assert.Equal(before, await OriginalRows());
        Assert.All(await db.Resources.Include(x => x.Configuration).ToArrayAsync(), x => Assert.Null(x.Configuration));
        Assert.Empty(await db.ResourceConfigurations.ToArrayAsync());
        Assert.False(db.Database.HasPendingModelChanges());
        Assert.Empty(await db.Database.GetPendingMigrationsAsync());
        db.ResourceConfigurations.Add(Configuration(first.Id, Original));
        await db.SaveChangesAsync();
        db.ChangeTracker.Clear();
        // Only this disposable fixture is downgraded; the new table's documents are intentionally removed.
        await migrator.MigrateAsync(PreviousMigration);
        Assert.Equal(before, await OriginalRows());
        Assert.Equal(0L, await Scalar<long>("SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_name='resource_configurations'"));
        await migrator.MigrateAsync();
        Assert.Equal(before, await OriginalRows());
        Assert.Empty(await db.ResourceConfigurations.ToArrayAsync());
    }

    [PostgreSqlFact]
    public async Task Existing_http_contracts_and_metadata_updates_preserve_independent_configuration()
    {
        var resource = Resource();
        await using (var db = CreateContext())
        {
            await db.Database.MigrateAsync();
            resource.Configuration = Configuration(resource.Id, Original);
            db.Resources.Add(resource);
            await db.SaveChangesAsync();
        }
        using var factory = new PostgreSqlApiFactory(ConnectionString);
        using var client = factory.CreateClient(new WebApplicationFactoryClientOptions { BaseAddress = new Uri("https://localhost") });
        var loaded = await client.GetFromJsonAsync<JsonElement>($"/resources/{resource.Id}");
        Assert.Equal(new[] { "createdAtUtc", "id", "name", "type", "x", "y" }, loaded.EnumerateObject().Select(x => x.Name).Order());
        var scoped = await client.GetFromJsonAsync<JsonElement>($"/designs/{LegacyDesign.Id}/resources");
        Assert.Equal(new[] { "createdAtUtc", "designId", "id", "name", "type", "x", "y" }, scoped[0].EnumerateObject().Select(x => x.Name).Order());
        var update = await client.PutAsJsonAsync($"/resources/{resource.Id}", new
        { name = "Renamed metadata", type = resource.Type, x = 4, y = 5 });
        Assert.Equal(HttpStatusCode.OK, update.StatusCode);
        var created = await client.PostAsJsonAsync("/resources", new
        { name = "Still unconfigured", type = "custom.legacy", x = 4, y = 5, designId = LegacyDesign.Id });
        Assert.Equal(HttpStatusCode.Created, created.StatusCode);
        await using (var db = CreateContext())
        {
            AssertJson(Original, (await db.ResourceConfigurations.SingleAsync()).Configuration);
            var saved = await db.Resources.Include(x => x.Configuration).SingleAsync(x => x.Id == resource.Id);
            Assert.Equal("Renamed metadata", saved.Name);
            Assert.Equal((4, 5), (saved.X, saved.Y));
            Assert.Null((await db.Resources.Include(x => x.Configuration).SingleAsync(x => x.Id != resource.Id)).Configuration);
        }
        Assert.Equal(HttpStatusCode.Conflict, (await client.DeleteAsync($"/designs/{LegacyDesign.Id}")).StatusCode);
        Assert.Equal(HttpStatusCode.NoContent, (await client.DeleteAsync($"/resources/{resource.Id}")).StatusCode);
        await using (var db = CreateContext())
        {
            Assert.Empty(await db.ResourceConfigurations.ToArrayAsync());
            Assert.Single(await db.Resources.ToArrayAsync());
        }
        Assert.Equal(0, factory.Cloud.Calls);
    }

    private static ResourceEntity Resource() => new()
    {
        Id = Guid.NewGuid(), DesignId = LegacyDesign.Id, Name = "Fixture resource", Type = "gcp.storage.bucket",
        X = 3, Y = 2, CreatedAtUtc = new DateTime(2026, 10, 25, 0, 0, 0, DateTimeKind.Utc)
    };

    private static ResourceConfiguration Configuration(Guid resourceId, string json, int version = 1) => new()
    { ResourceId = resourceId, SchemaVersion = version, Configuration = json };

    private static void AssertJson(string expected, string actual) =>
        Assert.True(JsonNode.DeepEquals(JsonNode.Parse(expected), JsonNode.Parse(actual)), "JSON semantics must survive native jsonb materialization.");

    private Task<string> OriginalRows() => Scalar<string>("""
        SELECT jsonb_build_object(
            'designs',(SELECT jsonb_agg(to_jsonb(d) ORDER BY "Id") FROM designs d),
            'resources',(SELECT jsonb_agg(to_jsonb(r) ORDER BY "Id") FROM resources r),
            'resource_types',(SELECT jsonb_agg(to_jsonb(t) ORDER BY "Id") FROM resource_types t))::text
        """);
}
