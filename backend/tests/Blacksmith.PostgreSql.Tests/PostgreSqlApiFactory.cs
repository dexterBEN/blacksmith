using Blacksmith.Domain.Entities;
using Blacksmith.Infrastructure.Persistence;
using CloudServices.Core;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;

namespace Blacksmith.PostgreSql.Tests;

internal sealed class PostgreSqlApiFactory(string connectionString, SaveGate? gate = null)
    : WebApplicationFactory<Program>
{
    public NoCloudStorage Cloud { get; } = new();
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing");
        builder.ConfigureTestServices(services =>
        {
            services.RemoveAll<BlacksmithDbContext>();
            services.AddScoped(_ =>
            {
                var options = new DbContextOptionsBuilder<BlacksmithDbContext>().UseNpgsql(connectionString);
                if (gate is not null) options.AddInterceptors(gate);
                return new BlacksmithDbContext(options.Options);
            });
            services.RemoveAll<ICloudStorageService>();
            services.AddSingleton<ICloudStorageService>(Cloud);
        });
    }
}

internal sealed class NoCloudStorage : ICloudStorageService
{
    private int _calls;
    public int Calls => _calls;
    public Task<string> CreateBucketAsync(string projectId, string bucketName)
    {
        Interlocked.Increment(ref _calls);
        throw new InvalidOperationException("Design/resource management must not provision cloud services.");
    }
}

// Pause after the service's existence/emptiness check, immediately before the real PostgreSQL write.
internal sealed class SaveGate(Func<DbContext, bool> shouldPause) : SaveChangesInterceptor
{
    private int _entered;
    public TaskCompletionSource Entered { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
    public TaskCompletionSource Continue { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);

    public override async ValueTask<InterceptionResult<int>> SavingChangesAsync(
        DbContextEventData eventData, InterceptionResult<int> result, CancellationToken cancellationToken = default)
    {
        if (eventData.Context is { } context && shouldPause(context) && Interlocked.Exchange(ref _entered, 1) == 0)
        {
            Entered.TrySetResult();
            await Continue.Task.WaitAsync(TimeSpan.FromSeconds(30), cancellationToken);
        }
        return result;
    }

    public static SaveGate DesignDelete() => new(context =>
        context.ChangeTracker.Entries<DesignEntity>().Any(entry => entry.State == EntityState.Deleted));
    public static SaveGate ResourceCreate() => new(context =>
        context.ChangeTracker.Entries<ResourceEntity>().Any(entry => entry.State == EntityState.Added));
}
