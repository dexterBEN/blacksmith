// Test support only: run the unchanged API against a new isolated database.
// The launcher copies this project to a temporary backend/test-host directory.
using System.Diagnostics;
using System.Text.Json;
using Blacksmith.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Npgsql;

var configured = Environment.GetEnvironmentVariable("ConnectionStrings__BlacksmithDb")
    ?? throw new InvalidOperationException("The backend Dev Container must provide its existing database configuration.");
var admin = new NpgsqlConnectionStringBuilder(configured) { Database = "postgres", Pooling = false };
var directory = Path.GetFullPath(args[0]);
var metadataPath = Path.Combine(directory, "metadata.json");
if (args.Length > 1 && args[1] == "verify")
{
    using var metadata = JsonDocument.Parse(await File.ReadAllTextAsync(metadataPath));
    var db = metadata.RootElement.GetProperty("database").GetString()!;
    if (!db.StartsWith("blacksmith_front_smoke_", StringComparison.Ordinal)) throw new InvalidOperationException();
    var cs = new NpgsqlConnectionStringBuilder(admin.ConnectionString) { Database = db };
    await using var connection = new NpgsqlConnection(cs.ConnectionString);
    await connection.OpenAsync();
    await using var query = new NpgsqlCommand(
        "SELECT \"Name\", (SELECT COUNT(*) FROM resources WHERE design_id = @id) FROM designs WHERE \"Id\" = @id", connection);
    query.Parameters.AddWithValue("id", Guid.Parse(args[2]));
    await using var row = await query.ExecuteReaderAsync();
    if (!await row.ReadAsync() || row.GetString(0) != args[3] || row.GetInt64(1) != 0)
        throw new InvalidOperationException("SQL read-back did not match the frontend Design.");
    Console.WriteLine(JsonSerializer.Serialize(new { verified = true, database = db, id = args[2], name = row.GetString(0), resources = row.GetInt64(1) }));
    return;
}

var databaseName = "blacksmith_front_smoke_" + Guid.NewGuid().ToString("N");
var test = new NpgsqlConnectionStringBuilder(admin.ConnectionString) { Database = databaseName };
var port = int.Parse(args[1]);
if (port is < 1024 or > 65535) throw new ArgumentException("Choose a non-privileged test port.");
await using var administrative = new NpgsqlConnection(admin.ConnectionString);
await administrative.OpenAsync();
await using (var create = new NpgsqlCommand($"CREATE DATABASE \"{databaseName}\"", administrative))
    await create.ExecuteNonQueryAsync();
Process? api = null;
try
{
    await using (var db = new BlacksmithDbContext(new DbContextOptionsBuilder<BlacksmithDbContext>()
        .UseNpgsql(test.ConnectionString).Options))
        await db.Database.MigrateAsync(); // Existing migrations, exclusively in this new database.
    var start = new ProcessStartInfo("dotnet") { UseShellExecute = false, WorkingDirectory = directory };
    start.ArgumentList.Add(Path.Combine(directory, "src/CloudServices.Api/bin/Release/net8.0/CloudServices.Api.dll"));
    start.Environment["ConnectionStrings__BlacksmithDb"] = test.ConnectionString;
    start.Environment["ASPNETCORE_URLS"] = $"http://0.0.0.0:{port}";
    start.Environment["ASPNETCORE_ENVIRONMENT"] = "Production";
    // The Design controller must work without usable GCP credentials.
    start.Environment["GOOGLE_APPLICATION_CREDENTIALS"] = "/nonexistent/blacksmith-no-cloud-credentials.json";
    api = Process.Start(start) ?? throw new InvalidOperationException("API did not start.");
    await File.WriteAllTextAsync(metadataPath, JsonSerializer.Serialize(new { database = databaseName, port, api_pid = api.Id }));
    Console.WriteLine($"BLACKSMITH_DESIGN_BACKEND_STARTED database={databaseName} port={port}");
    while (!File.Exists(Path.Combine(directory, "stop")) && !api.HasExited) await Task.Delay(250);
    if (api.HasExited && api.ExitCode != 0) throw new InvalidOperationException("API exited unexpectedly.");
}
finally
{
    if (api is { HasExited: false }) { api.Kill(entireProcessTree: true); await api.WaitForExitAsync(); }
    NpgsqlConnection.ClearAllPools();
    await using var drop = new NpgsqlCommand($"DROP DATABASE \"{databaseName}\" WITH (FORCE)", administrative);
    await drop.ExecuteNonQueryAsync();
    Console.WriteLine($"BLACKSMITH_DESIGN_BACKEND_CLEANED database={databaseName}");
}
