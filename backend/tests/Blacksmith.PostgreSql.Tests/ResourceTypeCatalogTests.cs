using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Blacksmith.Domain.Entities;
using Blacksmith.Infrastructure.Persistence;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql;
using Xunit;

namespace Blacksmith.PostgreSql.Tests;

public sealed class ResourceTypeCatalogTests : PostgreSqlTestDatabase
{
    private const string PreviousMigration = "20261019050301_AddDesignOwnership";
    private static readonly Guid StorageId = new("10000000-0000-0000-0000-000000000002");
    private static readonly string[] Codes = ["database", "gateway", "load-balancer", "network", "storage", "virtual-machine"];

    [PostgreSqlFact]
    public async Task Empty_database_seeds_fixed_catalog_with_nullable_indexed_restrictive_resource_reference()
    {
        await using var db = CreateContext();
        await db.Database.MigrateAsync();
        Assert.Equal(Codes, await db.ResourceTypes.OrderBy(x => x.Code).Select(x => x.Code).ToArrayAsync());
        Assert.Equal("storage", (await db.ResourceTypes.SingleAsync(x => x.Id == StorageId)).Code);
        Assert.Equal("YES", await Scalar<string>("SELECT is_nullable FROM information_schema.columns WHERE table_name='resources' AND column_name='resource_type_id'"));
        Assert.Equal("RESTRICT", await Scalar<string>("SELECT delete_rule FROM information_schema.referential_constraints WHERE constraint_name='FK_resources_resource_types_resource_type_id'"));
        Assert.Equal(1L, await Scalar<long>("SELECT count(*) FROM pg_indexes WHERE tablename='resources' AND indexname='IX_resources_resource_type_id'"));
        Assert.Equal(1L, await Scalar<long>("SELECT count(*) FROM information_schema.table_constraints WHERE table_name='resource_types' AND constraint_type='UNIQUE' AND constraint_name='AK_resource_types_Code'"));
        Assert.False(db.Database.HasPendingModelChanges());
        await db.Database.MigrateAsync();
        Assert.Equal(6, await db.ResourceTypes.CountAsync());
        Assert.Equal(4, (await db.Database.GetAppliedMigrationsAsync()).Count());
    }

    [PostgreSqlFact]
    public async Task Populated_migration_preserves_original_values_and_only_backfills_exact_generic_codes()
    {
        await using var db = CreateContext();
        var migrator = db.GetService<IMigrator>();
        await migrator.MigrateAsync(PreviousMigration);
        var texts = Codes.Concat(new[] { "gcp.storage.bucket", "custom.type", "Storage", " storage ", "vm", "" }).ToArray();
        for (var index = 0; index < texts.Length; index++)
        {
            var created = new DateTime(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc).AddMinutes(index);
            await db.Database.ExecuteSqlInterpolatedAsync($"""
                INSERT INTO resources ("Id", "Name", "Type", x, y, created_at_utc, design_id)
                VALUES ({Guid.NewGuid()}, {"  Historical é " + index + "  "}, {texts[index]}, {-index}, {index + 3}, {created}, {LegacyDesign.Id})
                """);
        }
        var before = await ReadOriginalRows();
        await migrator.MigrateAsync();
        Assert.Equal(before, await ReadOriginalRows());
        var types = await db.ResourceTypes.ToDictionaryAsync(x => x.Code, x => x.Id);
        var resources = await db.Resources.AsNoTracking().ToArrayAsync();
        Assert.Equal(texts.Length, resources.Length);
        foreach (var resource in resources)
            Assert.Equal(types.TryGetValue(resource.Type, out var id) ? id : (Guid?)null, resource.ResourceTypeId);

        // Removing the new classification must preserve the previous design ownership and legacy fields.
        await migrator.MigrateAsync(PreviousMigration);
        Assert.Equal(before, await ReadOriginalRows());
        Assert.Equal(0L, await Scalar<long>("SELECT count(*) FROM information_schema.tables WHERE table_name='resource_types'"));
        Assert.Equal(0L, await Scalar<long>("SELECT count(*) FROM information_schema.columns WHERE table_name='resources' AND column_name='resource_type_id'"));
        await migrator.MigrateAsync();
        Assert.Equal(before, await ReadOriginalRows());
        Assert.Equal(StorageId, (await db.ResourceTypes.SingleAsync(x => x.Code == "storage")).Id);
    }

    [PostgreSqlFact]
    public async Task PostgreSql_enforces_unique_codes_valid_references_and_restrictive_deletion()
    {
        await using var db = CreateContext();
        await db.Database.MigrateAsync();
        var duplicate = await Assert.ThrowsAsync<PostgresException>(() => db.Database.ExecuteSqlInterpolatedAsync($"""
            INSERT INTO resource_types ("Id", "Code", "DisplayName", "Category")
            VALUES ({Guid.NewGuid()}, {"storage"}, {"Duplicate"}, {"Storage"})
            """));
        Assert.Equal(PostgresErrorCodes.UniqueViolation, duplicate.SqlState);
        Assert.Equal("AK_resource_types_Code", duplicate.ConstraintName);
        var invalid = await Assert.ThrowsAsync<PostgresException>(() => db.Database.ExecuteSqlInterpolatedAsync($"""
            INSERT INTO resources ("Id", "Name", "Type", x, y, design_id, resource_type_id)
            VALUES ({Guid.NewGuid()}, {"Orphan"}, {"custom.type"}, {0}, {0}, {LegacyDesign.Id}, {Guid.NewGuid()})
            """));
        Assert.Equal(PostgresErrorCodes.ForeignKeyViolation, invalid.SqlState);
        Assert.Equal(BlacksmithDbContext.ResourceTypeForeignKey, invalid.ConstraintName);

        var child = new ResourceEntity { Id = Guid.NewGuid(), Name = "Bucket", Type = "gcp.storage.bucket",
            DesignId = LegacyDesign.Id, ResourceTypeId = StorageId };
        db.Resources.Add(child);
        await db.SaveChangesAsync();
        var deletion = await Assert.ThrowsAsync<PostgresException>(() => db.Database.ExecuteSqlInterpolatedAsync(
            $"DELETE FROM resource_types WHERE \"Id\" = {StorageId}"));
        Assert.Equal(PostgresErrorCodes.ForeignKeyViolation, deletion.SqlState);
        Assert.Equal(BlacksmithDbContext.ResourceTypeForeignKey, deletion.ConstraintName);
        db.ChangeTracker.Clear();
        Assert.Equal(StorageId, (await db.Resources.SingleAsync()).ResourceTypeId);
        Assert.Equal(6, await db.ResourceTypes.CountAsync());
        // Unknown legacy strings may remain unclassified during the transition.
        await db.Database.ExecuteSqlInterpolatedAsync($"UPDATE resources SET resource_type_id = NULL WHERE \"Id\" = {child.Id}");
        db.ChangeTracker.Clear();
        Assert.Null((await db.Resources.SingleAsync()).ResourceTypeId);
        Assert.Equal("gcp.storage.bucket", (await db.Resources.SingleAsync()).Type);
    }

    [PostgreSqlFact]
    public async Task Concurrent_catalog_delete_after_reference_validation_returns_404_without_orphan()
    {
        await using (var db = CreateContext()) await db.Database.MigrateAsync();
        var gate = SaveGate.ResourceCreate();
        using var factory = new PostgreSqlApiFactory(ConnectionString, gate);
        using var client = factory.CreateClient(new WebApplicationFactoryClientOptions { BaseAddress = new Uri("https://localhost") });
        var creating = client.PostAsJsonAsync("/resources", new
        { name = "Bucket", type = "gcp.storage.bucket", designId = LegacyDesign.Id, resourceTypeId = StorageId });
        try
        {
            await gate.Entered.Task.WaitAsync(TimeSpan.FromSeconds(15));
            await using var competitor = CreateContext();
            await competitor.Database.ExecuteSqlInterpolatedAsync($"DELETE FROM resource_types WHERE \"Id\" = {StorageId}");
        }
        finally { gate.Continue.TrySetResult(); }
        var response = await creating;
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
        Assert.Equal("Resource type not found.",
            (await response.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("error").GetString());
        await using var verification = CreateContext();
        Assert.Empty(await verification.Resources.ToListAsync());
        Assert.False(await verification.ResourceTypes.AnyAsync(x => x.Id == StorageId));
        Assert.True(await verification.Designs.AnyAsync(x => x.Id == LegacyDesign.Id));
        Assert.Equal(0, factory.Cloud.Calls);
    }

    private async Task<OriginalRow[]> ReadOriginalRows()
    {
        await using var connection = new NpgsqlConnection(ConnectionString);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand("SELECT \"Id\", \"Name\", \"Type\", x, y, created_at_utc, design_id FROM resources ORDER BY \"Id\"", connection);
        await using var reader = await command.ExecuteReaderAsync();
        var rows = new List<OriginalRow>();
        while (await reader.ReadAsync()) rows.Add(new OriginalRow(reader.GetGuid(0), reader.GetString(1),
            reader.GetString(2), reader.GetInt32(3), reader.GetInt32(4), reader.GetDateTime(5), reader.GetGuid(6)));
        return rows.ToArray();
    }

    private sealed record OriginalRow(Guid Id, string Name, string Type, int X, int Y, DateTime CreatedAtUtc, Guid DesignId);
}
