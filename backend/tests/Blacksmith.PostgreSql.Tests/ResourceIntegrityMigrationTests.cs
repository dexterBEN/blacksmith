using Blacksmith.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql;
using Xunit;

namespace Blacksmith.PostgreSql.Tests;

public sealed class ResourceIntegrityMigrationTests : PostgreSqlTestDatabase
{
    private const string Previous = "20261025205111_AddResourceConfigurations";

    [PostgreSqlFact]
    public async Task Populated_legacy_resources_and_configuration_survive_with_revision_one_and_no_viewport_constraint()
    {
        await using var db = CreateContext();
        var migrator = db.GetService<IMigrator>();
        await migrator.MigrateAsync(Previous);
        var a = Guid.NewGuid(); var b = Guid.NewGuid();
        await Insert(db, a, -37, 900);
        await Insert(db, b, int.MaxValue, int.MinValue);
        var historical = """{"future":true}""";
        await db.Database.ExecuteSqlInterpolatedAsync($"INSERT INTO resource_configurations(resource_id,schema_version,configuration) VALUES ({a},2,{historical}::jsonb)");
        var before = await Rows();
        var configuration = await Scalar<string>("SELECT configuration::text FROM resource_configurations");
        await migrator.MigrateAsync();
        Assert.Equal(before, await Rows());
        Assert.Equal(configuration, await Scalar<string>("SELECT configuration::text FROM resource_configurations"));
        Assert.Equal(2L, await Scalar<long>("SELECT count(*) FROM resources WHERE revision=1"));
        Assert.Equal(1L, await Scalar<long>("SELECT count(*) FROM pg_indexes WHERE indexname='UX_resources_design_id_x_y' AND indexdef LIKE 'CREATE UNIQUE INDEX%'"));
        Assert.Equal(0L, await Scalar<long>("SELECT count(*) FROM pg_constraint WHERE conrelid='resources'::regclass AND contype='c'"));
        Assert.False(db.Database.HasPendingModelChanges());
        Assert.Empty(await db.Database.GetPendingMigrationsAsync());
        Assert.Null((await db.Resources.Include(x => x.Configuration).SingleAsync(x => x.Id == b)).Configuration);
        Assert.Equal(2, (await db.ResourceConfigurations.SingleAsync()).SchemaVersion);
        var collision = await Assert.ThrowsAsync<PostgresException>(() => Insert(db, Guid.NewGuid(), -37, 900));
        Assert.Equal(PostgresErrorCodes.UniqueViolation, collision.SqlState);
        Assert.Equal("UX_resources_design_id_x_y", collision.ConstraintName);
    }

    [PostgreSqlFact]
    public async Task Duplicate_tile_preflight_aborts_without_schema_or_data_loss()
    {
        await using var db = CreateContext();
        var migrator = db.GetService<IMigrator>();
        await migrator.MigrateAsync(Previous);
        await Insert(db, Guid.NewGuid(), 4, 5);
        await Insert(db, Guid.NewGuid(), 4, 5);
        var before = await Rows();
        var failure = await Assert.ThrowsAsync<PostgresException>(() => migrator.MigrateAsync());
        Assert.Equal(PostgresErrorCodes.UniqueViolation, failure.SqlState);
        Assert.Contains("Duplicate Resource tile occupancy", failure.MessageText);
        Assert.Equal(before, await Rows());
        Assert.Equal(0L, await Scalar<long>("SELECT count(*) FROM information_schema.columns WHERE table_name='resources' AND column_name='revision'"));
        Assert.Equal(0L, await Scalar<long>("SELECT count(*) FROM pg_indexes WHERE indexname='UX_resources_design_id_x_y'"));
        Assert.Equal(5L, await Scalar<long>("SELECT count(*) FROM \"__EFMigrationsHistory\""));
    }

    private static Task<int> Insert(Blacksmith.Infrastructure.Persistence.BlacksmithDbContext db, Guid id, int x, int y) =>
        db.Database.ExecuteSqlInterpolatedAsync($"INSERT INTO resources(\"Id\",design_id,\"Name\",\"Type\",x,y) VALUES ({id},{LegacyDesign.Id},{"Historical label"},{"gcp.storage.bucket"},{x},{y})");
    private Task<string> Rows() => Scalar<string>("SELECT jsonb_agg(to_jsonb(r)-'revision' ORDER BY \"Id\")::text FROM resources r");
}
