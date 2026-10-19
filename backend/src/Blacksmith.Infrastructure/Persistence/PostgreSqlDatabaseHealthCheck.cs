using Blacksmith.Application.Interfaces;
using Microsoft.Extensions.Configuration;
using Npgsql;

namespace Blacksmith.Infrastructure.Persistence;

public sealed class PostgreSqlDatabaseHealthCheck(IConfiguration configuration) : IDatabaseHealthCheck
{
    public async Task<DateTime> GetDatabaseTimeAsync(CancellationToken ct)
    {
        await using var connection = new NpgsqlConnection(configuration.GetConnectionString("BlacksmithDb"));
        await connection.OpenAsync(ct);
        await using var command = new NpgsqlCommand("select now()", connection);
        return (DateTime)(await command.ExecuteScalarAsync(ct)
            ?? throw new InvalidOperationException("Database time was not returned."));
    }
}
