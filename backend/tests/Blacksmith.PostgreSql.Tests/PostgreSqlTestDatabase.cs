using Blacksmith.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Npgsql;
using Xunit;

namespace Blacksmith.PostgreSql.Tests;

public sealed class PostgreSqlFactAttribute : FactAttribute
{
    public PostgreSqlFactAttribute()
    {
        if (string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("BLACKSMITH_TEST_POSTGRES")))
            Skip = "Set BLACKSMITH_TEST_POSTGRES to an isolated PostgreSQL server with CREATE DATABASE permission.";
    }
}

// Every test gets a new database. The supplied administrative database is never migrated or cleared.
public abstract class PostgreSqlTestDatabase : IAsyncLifetime
{
    private readonly string _databaseName = "blacksmith_issue7_" + Guid.NewGuid().ToString("N");
    private readonly string _adminConnection = Environment.GetEnvironmentVariable("BLACKSMITH_TEST_POSTGRES")
        ?? throw new InvalidOperationException("BLACKSMITH_TEST_POSTGRES is required.");
    public string ConnectionString => new NpgsqlConnectionStringBuilder(_adminConnection)
    { Database = _databaseName, Pooling = false }.ConnectionString;

    public async Task InitializeAsync()
    {
        await using var admin = new NpgsqlConnection(_adminConnection);
        await admin.OpenAsync();
        await using var command = new NpgsqlCommand($"CREATE DATABASE \"{_databaseName}\"", admin);
        await command.ExecuteNonQueryAsync();
    }

    public async Task DisposeAsync()
    {
        // Only the random database created by this test instance may be dropped.
        if (!_databaseName.StartsWith("blacksmith_issue7_", StringComparison.Ordinal)
            || _databaseName.Length != "blacksmith_issue7_".Length + 32)
            throw new InvalidOperationException("Unexpected test database name.");
        await using var admin = new NpgsqlConnection(_adminConnection);
        await admin.OpenAsync();
        await using var command = new NpgsqlCommand($"DROP DATABASE IF EXISTS \"{_databaseName}\"", admin);
        await command.ExecuteNonQueryAsync();
    }

    protected BlacksmithDbContext CreateContext() => new(
        new DbContextOptionsBuilder<BlacksmithDbContext>().UseNpgsql(ConnectionString).Options);

    protected async Task<T> Scalar<T>(string sql)
    {
        await using var connection = new NpgsqlConnection(ConnectionString);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand(sql, connection);
        return (T)(await command.ExecuteScalarAsync())!;
    }
}
