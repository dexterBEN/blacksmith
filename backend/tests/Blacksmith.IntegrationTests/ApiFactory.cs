using Blacksmith.Application.Interfaces;
using Blacksmith.Infrastructure.Persistence;
using CloudServices.Core;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;

namespace Blacksmith.IntegrationTests;

public sealed class ApiFactory(SqliteConnection connection) : WebApplicationFactory<Program>
{
    public RecordingCloudStorage Cloud { get; } = new();

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing");
        builder.ConfigureTestServices(services =>
        {
            services.RemoveAll<BlacksmithDbContext>();
            services.AddScoped(_ => new BlacksmithDbContext(
                new DbContextOptionsBuilder<BlacksmithDbContext>().UseSqlite(connection).Options));
            services.RemoveAll<ICloudStorageService>();
            services.AddSingleton<ICloudStorageService>(Cloud);
            services.RemoveAll<IDatabaseHealthCheck>();
            services.AddSingleton<IDatabaseHealthCheck, FixedDatabaseHealthCheck>();
        });
    }
}

public sealed class FixedDatabaseHealthCheck : IDatabaseHealthCheck
{
    public static DateTime DatabaseTime { get; } = new(2026, 1, 2, 3, 4, 5, DateTimeKind.Utc);

    public Task<DateTime> GetDatabaseTimeAsync(CancellationToken ct)
    {
        ct.ThrowIfCancellationRequested();
        return Task.FromResult(DatabaseTime);
    }
}

public sealed class RecordingCloudStorage : ICloudStorageService
{
    public List<(string ProjectId, string BucketName)> Calls { get; } = [];

    public Task<string> CreateBucketAsync(string projectId, string bucketName)
    {
        Calls.Add((projectId, bucketName));
        return Task.FromResult(bucketName);
    }
}
