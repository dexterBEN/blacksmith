using System.Collections.Concurrent;
using Blacksmith.Application.Interfaces;
using Blacksmith.Infrastructure.Persistence;
using CloudServices.Api;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;

namespace Blacksmith.TestSupport;

// Test-only composition. Production never has a configuration switch to choose a fake provider.
public sealed class DeploymentApiFactory(Action<DbContextOptionsBuilder<BlacksmithDbContext>> database,
    string environment = "Development", bool enabled = true) : WebApplicationFactory<DeploymentPolicy>
{
    public const string TestToken = "fixture-only-never-authorizes-real-cloud-0000";
    public RecordingBucketProvider Cloud { get; } = new();
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment(environment);
        builder.ConfigureAppConfiguration((_, config) => config.AddInMemoryCollection(new Dictionary<string, string?> {
            ["BlacksmithDeployment:Enabled"] = enabled.ToString(),
            ["BlacksmithDeployment:Token"] = TestToken,
            ["BlacksmithDeployment:ApprovedProjects:0"] = "example-project-123"
        }));
        builder.ConfigureTestServices(services => {
            services.RemoveAll<BlacksmithDbContext>();
            services.AddScoped(_ => { var options = new DbContextOptionsBuilder<BlacksmithDbContext>(); database(options); return new BlacksmithDbContext(options.Options); });
            services.RemoveAll<ICloudBucketProvisioner>();
            services.AddSingleton<ICloudBucketProvisioner>(Cloud);
        });
    }
}

public sealed class RecordingBucketProvider : ICloudBucketProvisioner
{
    private int _creates, _inspections;
    public int Creates => _creates;
    public int Inspections => _inspections;
    public int Buckets => _buckets.Count;
    private readonly ConcurrentDictionary<string,int> _attempts = new();
    public TaskCompletionSource? Entered { get; set; }
    public TaskCompletionSource? Continue { get; set; }
    public Func<Task>? BeforeCreate { get; set; }
    private readonly ConcurrentDictionary<string, (CloudBucketTarget Target, string Marker)> _buckets = new();
    public async Task<CloudBucketResult> EnsureAsync(CloudBucketTarget target, string marker, CancellationToken ct)
    {
        Interlocked.Increment(ref _creates);
        if (BeforeCreate is not null) await BeforeCreate();
        Entered?.TrySetResult();
        if (Continue is not null) await Continue.Task.WaitAsync(ct);
        var attempt = _attempts.AddOrUpdate(target.BucketName,1,(_,previous)=>previous+1);
        if (target.BucketName.EndsWith("-retry") && attempt==1) return new("failed","provider_rejected");
        if (target.BucketName.EndsWith("-reject")) return new("failed", "provider_rejected");
        _buckets.TryAdd(target.BucketName, (target, marker));
        if (target.BucketName.EndsWith("-lost") || target.BucketName.EndsWith("-retry")) return new("unknown", "provider_timeout");
        return Verify(target, marker);
    }
    public Task<CloudBucketResult> InspectAsync(CloudBucketTarget target, string marker, CancellationToken ct)
    {
        Interlocked.Increment(ref _inspections);
        return Task.FromResult(Verify(target, marker));
    }
    public void AddUnrelated(CloudBucketTarget target) => _buckets[target.BucketName] = (target, "unrelated-marker");
    private CloudBucketResult Verify(CloudBucketTarget target, string marker) =>
        !_buckets.TryGetValue(target.BucketName, out var found) ? new("unknown", "bucket_not_found") :
        found.Target != target || found.Marker != marker ? new("failed", "unrelated_bucket") :
        new("succeeded", "verified", new("123456789", target.BucketName, "1"));
}
