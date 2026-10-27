using Blacksmith.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql;
using Xunit;

namespace Blacksmith.PostgreSql.Tests;

public sealed class MigrationTests : PostgreSqlTestDatabase
{
    private const string PreviousMigration = "20251229011642_AddResourcesTable";

    [PostgreSqlFact]
    public async Task Empty_database_migrates_to_required_indexed_restrictive_ownership()
    {
        await using var db = CreateContext();
        await db.Database.MigrateAsync();
        var design = await db.Designs.SingleAsync();
        Assert.Equal(LegacyDesign.Id, design.Id);
        Assert.Equal(LegacyDesign.Name, design.Name);
        Assert.Empty(await db.Resources.ToListAsync());
        Assert.Equal("NO", await Scalar<string>("SELECT is_nullable FROM information_schema.columns WHERE table_name='resources' AND column_name='design_id'"));
        Assert.Equal("RESTRICT", await Scalar<string>("SELECT delete_rule FROM information_schema.referential_constraints WHERE constraint_name='FK_resources_designs_design_id'"));
        Assert.Equal(1L, await Scalar<long>("SELECT count(*) FROM pg_indexes WHERE tablename='resources' AND indexname='IX_resources_design_id'"));
        Assert.Equal(7, (await db.Database.GetAppliedMigrationsAsync()).Count());
        Assert.False(db.Database.HasPendingModelChanges());
        // Applying again must leave both the data and migration history unchanged.
        await db.Database.MigrateAsync();
        Assert.Equal(1, await db.Designs.CountAsync());
    }

    [PostgreSqlFact]
    public async Task Populated_database_preserves_every_legacy_value_and_backfills_stable_owner()
    {
        await using var db = CreateContext();
        var migrator = db.GetService<IMigrator>();
        await migrator.MigrateAsync(PreviousMigration);
        var firstId = Guid.NewGuid();
        var secondId = Guid.NewGuid();
        var firstTime = new DateTime(2025, 12, 29, 1, 2, 3, DateTimeKind.Utc);
        var secondTime = firstTime.AddHours(5);
        await db.Database.ExecuteSqlInterpolatedAsync($"""
            INSERT INTO resources ("Id", "Name", "Type", x, y, created_at_utc) VALUES
            ({firstId}, {"  Old bucket é  "}, {"gcp.storage.bucket"}, {-37}, {9}, {firstTime}),
            ({secondId}, {"Second"}, {"custom.type"}, {0}, {-42}, {secondTime})
            """);
        var before = await ReadLegacyRows();
        await migrator.MigrateAsync();
        Assert.Equal(before, await ReadLegacyRows());
        var resources = await db.Resources.AsNoTracking().ToListAsync();
        Assert.Equal(2, resources.Count);
        Assert.All(resources, resource => Assert.Equal(LegacyDesign.Id, resource.DesignId));
        Assert.Equal(LegacyDesign.Id, (await db.Designs.SingleAsync()).Id);

        // Down retains the old resources table and its six original values, but necessarily loses ownership metadata.
        await migrator.MigrateAsync(PreviousMigration);
        Assert.Equal(before, await ReadLegacyRows());
        Assert.Equal(0L, await Scalar<long>("SELECT count(*) FROM information_schema.tables WHERE table_name='designs'"));
        Assert.Equal(0L, await Scalar<long>("SELECT count(*) FROM information_schema.columns WHERE table_name='resources' AND column_name='design_id'"));
        Assert.Equal(2, (await db.Database.GetAppliedMigrationsAsync()).Count());
    }

    [PostgreSqlFact]
    public async Task PostgreSql_rejects_missing_null_owners_and_restricts_parent_deletion_without_cascade()
    {
        await using var db = CreateContext();
        await db.Database.MigrateAsync();
        var resourceId = Guid.NewGuid();
        await db.Database.ExecuteSqlInterpolatedAsync($"""
            INSERT INTO resources ("Id", "Name", "Type", x, y, design_id)
            VALUES ({resourceId}, {"Child"}, {"generic"}, {0}, {0}, {LegacyDesign.Id})
            """);
        var deletion = await Assert.ThrowsAsync<PostgresException>(() => db.Database.ExecuteSqlInterpolatedAsync(
            $"DELETE FROM designs WHERE \"Id\" = {LegacyDesign.Id}"));
        Assert.Equal(PostgresErrorCodes.ForeignKeyViolation, deletion.SqlState);
        Assert.Equal("FK_resources_designs_design_id", deletion.ConstraintName);
        foreach (var missing in new[] { Guid.NewGuid(), Guid.Empty })
        {
            var orphan = await Assert.ThrowsAsync<PostgresException>(() => db.Database.ExecuteSqlInterpolatedAsync($"""
                INSERT INTO resources ("Id", "Name", "Type", x, y, design_id)
                VALUES ({Guid.NewGuid()}, {"Orphan"}, {"generic"}, {0}, {0}, {missing})
                """));
            Assert.Equal(PostgresErrorCodes.ForeignKeyViolation, orphan.SqlState);
        }
        var nullOwner = await Assert.ThrowsAsync<PostgresException>(() => db.Database.ExecuteSqlInterpolatedAsync($"""
            INSERT INTO resources ("Id", "Name", "Type", x, y, design_id)
            VALUES ({Guid.NewGuid()}, {"Orphan"}, {"generic"}, {0}, {0}, NULL)
            """));
        Assert.Equal(PostgresErrorCodes.NotNullViolation, nullOwner.SqlState);
        Assert.Equal(resourceId, (await db.Resources.SingleAsync()).Id);
        Assert.Equal(LegacyDesign.Id, (await db.Designs.SingleAsync()).Id);
    }

    private async Task<LegacyRow[]> ReadLegacyRows()
    {
        await using var connection = new NpgsqlConnection(ConnectionString);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand("SELECT \"Id\", \"Name\", \"Type\", x, y, created_at_utc FROM resources ORDER BY \"Id\"", connection);
        await using var reader = await command.ExecuteReaderAsync();
        var rows = new List<LegacyRow>();
        while (await reader.ReadAsync()) rows.Add(new LegacyRow(reader.GetGuid(0), reader.GetString(1),
            reader.GetString(2), reader.GetInt32(3), reader.GetInt32(4), reader.GetDateTime(5)));
        return rows.ToArray();
    }

    private sealed record LegacyRow(Guid Id, string Name, string Type, int X, int Y, DateTime CreatedAtUtc);
}
