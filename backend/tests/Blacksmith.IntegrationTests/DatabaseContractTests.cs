using System.Text.Json;
using Blacksmith.Domain.Entities;
using Blacksmith.Infrastructure.Persistence;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata;
using Xunit;

namespace Blacksmith.IntegrationTests;

public sealed class DatabaseContractTests
{
    [Fact]
    public async Task Database_ping_preserves_status_and_database_timestamp_fields()
    {
        using var connection = new SqliteConnection("Data Source=:memory:");
        using var factory = new ApiFactory(connection);
        using var client = factory.CreateClient(new WebApplicationFactoryClientOptions
        { BaseAddress = new Uri("https://localhost") });

        var response = await client.GetAsync("/db/ping");
        response.EnsureSuccessStatusCode();
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal(new[] { "dbTime", "status" },
            json.RootElement.EnumerateObject().Select(property => property.Name).Order());
        Assert.Equal("ok", json.RootElement.GetProperty("status").GetString());
        Assert.Equal(FixedDatabaseHealthCheck.DatabaseTime, json.RootElement.GetProperty("dbTime").GetDateTime());
    }

    [Fact]
    public void PostgreSql_model_matches_existing_snapshot_and_preserves_migration_ids()
    {
        using var db = CreatePostgreSqlModel();

        var migrations = db.Database.GetMigrations().ToArray();
        Assert.Equal(5, migrations.Length);
        Assert.Equal(new[] { "20251229003351_InitialCreate", "20251229011642_AddResourcesTable" }, migrations.Take(2));
        Assert.EndsWith("_AddDesignOwnership", migrations[2]);
        Assert.EndsWith("_AddResourceTypeCatalog", migrations[3]);
        Assert.EndsWith("_AddResourceConfigurations", migrations[4]);
        Assert.False(db.Database.HasPendingModelChanges());
    }

    [Fact]
    public void PostgreSql_mapping_keeps_existing_table_columns_and_constraints()
    {
        using var db = CreatePostgreSqlModel();
        Assert.Equal(4, db.Model.GetEntityTypes().Count());
        var entity = db.Model.FindEntityType(typeof(ResourceEntity))!;
        Assert.Equal(typeof(ResourceEntity), entity.ClrType);
        Assert.Equal("resources", entity.GetTableName());
        var table = StoreObjectIdentifier.Table("resources", null);
        Assert.Equal("Id", Assert.Single(entity.FindPrimaryKey()!.Properties).Name);
        Assert.Equal(200, entity.FindProperty("Name")!.GetMaxLength());
        Assert.Equal(100, entity.FindProperty("Type")!.GetMaxLength());
        Assert.All(entity.GetProperties().Where(property => property.Name != "ResourceTypeId"),
            property => Assert.False(property.IsNullable));
        Assert.True(entity.FindProperty("ResourceTypeId")!.IsNullable);
        Assert.Equal("resource_type_id", entity.FindProperty("ResourceTypeId")!.GetColumnName(table));
        Assert.Equal("x", entity.FindProperty("X")!.GetColumnName(table));
        Assert.Equal("y", entity.FindProperty("Y")!.GetColumnName(table));
        var timestamp = entity.FindProperty("CreatedAtUtc")!;
        Assert.Equal("created_at_utc", timestamp.GetColumnName(table));
        Assert.Equal("timestamp with time zone", timestamp.GetColumnType());
        Assert.Equal("NOW()", timestamp.GetDefaultValueSql());
        Assert.Equal("design_id", entity.FindProperty("DesignId")!.GetColumnName(table));
        Assert.Equal(2, entity.GetForeignKeys().Count());
        var foreignKey = entity.GetForeignKeys().Single(key => key.PrincipalEntityType.ClrType == typeof(DesignEntity));
        Assert.Equal(DeleteBehavior.Restrict, foreignKey.DeleteBehavior);
        Assert.Equal(typeof(DesignEntity), foreignKey.PrincipalEntityType.ClrType);
        Assert.Equal(BlacksmithDbContext.ResourceDesignForeignKey, foreignKey.GetConstraintName());
        Assert.Equal(2, entity.GetIndexes().Count());
        Assert.Contains(entity.GetIndexes(), index => Assert.Single(index.Properties).Name == "DesignId");
        Assert.Contains(entity.GetIndexes(), index => Assert.Single(index.Properties).Name == "ResourceTypeId");
        var typeKey = entity.GetForeignKeys().Single(key => key.PrincipalEntityType.ClrType == typeof(ResourceTypeEntity));
        Assert.Equal(DeleteBehavior.Restrict, typeKey.DeleteBehavior);
        Assert.Equal(BlacksmithDbContext.ResourceTypeForeignKey, typeKey.GetConstraintName());
        var type = db.Model.FindEntityType(typeof(ResourceTypeEntity))!;
        Assert.Equal("resource_types", type.GetTableName());
        Assert.Contains(type.GetKeys(), key => Assert.Single(key.Properties).Name == "Code");
    }

    private static BlacksmithDbContext CreatePostgreSqlModel() => new(
        new DbContextOptionsBuilder<BlacksmithDbContext>()
            .UseNpgsql("Host=localhost;Database=blacksmith_model_test;Username=unused").Options);
}
