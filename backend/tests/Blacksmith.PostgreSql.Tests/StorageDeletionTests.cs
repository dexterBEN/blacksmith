using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Blacksmith.Domain.Entities;
using Blacksmith.TestSupport;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace Blacksmith.PostgreSql.Tests;

public sealed class StorageDeletionTests : PostgreSqlTestDatabase
{
    private readonly Guid _resource = Guid.NewGuid(), _operation = Guid.NewGuid();
    private string Route => $"/designs/{LegacyDesign.Id}/resources/{_resource}/deletions/{_operation}";
    private static HttpClient Client(DeploymentApiFactory factory) => factory.CreateClient(new WebApplicationFactoryClientOptions { BaseAddress = new("https://localhost") });
    private DeploymentApiFactory Factory(RecordingBucketProvider? cloud = null) => new(o => o.UseNpgsql(ConnectionString), cloud: cloud);
    private async Task Seed(HttpClient client)
    {
        await using (var db = CreateContext()) {
            await db.Database.MigrateAsync();
            Assert.False(db.Database.HasPendingModelChanges());
        }
        using var request = new HttpRequestMessage(HttpMethod.Put, $"/designs/{LegacyDesign.Id}/resources/{_resource}/deployments/{Guid.NewGuid()}") {
            Content = JsonContent.Create(new {
                name = "Cloud Storage", type = "gcp.storage.bucket", resourceTypeId = "10000000-0000-0000-0000-000000000002", x = 0, y = 0,
                configuration = new { schemaVersion = 1, configuration = new { projectId = "example-project-123", bucketName = "blacksmith-delete-fixture", location = "europe-west9" } }
            })
        };
        request.Headers.Add("X-Blacksmith-Deploy-Consent", "true");
        request.Headers.TryAddWithoutValidation("If-None-Match", "*");
        Assert.Equal(HttpStatusCode.OK, (await client.SendAsync(request)).StatusCode);
    }
    private Task<HttpResponseMessage> Delete(HttpClient client)
    {
        var request = new HttpRequestMessage(HttpMethod.Put, Route);
        request.Headers.Add("X-Blacksmith-Delete-Consent", "true");
        request.Headers.TryAddWithoutValidation("If-Match", $"\"resource-{_resource:N}-r1\"");
        return client.SendAsync(request);
    }
    private static async Task<string> Status(HttpResponseMessage response)
    {
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        return (await response.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("status").GetString()!;
    }
    [PostgreSqlFact]
    public async Task Receipt_commit_precedes_cloud_and_cleanup_preserves_other_resources()
    {
        using var factory = Factory(); using var client = Client(factory);
        await Seed(client);
        await using (var db = CreateContext()) {
            db.Resources.Add(new() { Id = Guid.NewGuid(), DesignId = LegacyDesign.Id, Name = "Other", Type = "generic", X = 1 });
            await db.SaveChangesAsync();
        }
        factory.Cloud.BeforeDelete = async () => {
            await using var db = CreateContext();
            Assert.Equal("pending", (await db.StorageDeletions.SingleAsync()).Status);
            Assert.True(await db.Resources.AnyAsync(x => x.Id == _resource));
            Assert.Single(await db.ResourceConfigurations.ToListAsync());
        };
        Assert.Equal("succeeded", await Status(await Delete(client)));
        await using var verification = CreateContext();
        Assert.Equal("Other", (await verification.Resources.SingleAsync()).Name);
        Assert.Empty(await verification.ResourceConfigurations.ToListAsync());
        Assert.Empty(await verification.StorageDeployments.ToListAsync());
        Assert.Empty(await verification.StorageDeploymentAttempts.ToListAsync());
        Assert.Equal("succeeded", (await verification.StorageDeletions.SingleAsync()).Status);
        Assert.Single(await verification.StorageDeletionAttempts.ToListAsync());
        Assert.Equal(1, factory.Cloud.Deletes);
        Assert.Equal(6, await verification.ResourceTypes.CountAsync());
    }
    [PostgreSqlFact]
    public async Task Receipt_insert_failure_prevents_cloud_call_and_retains_all_original_data()
    {
        using var factory = Factory(); using var client = Client(factory);
        await Seed(client);
        await using (var db = CreateContext())
            await db.Database.ExecuteSqlRawAsync("ALTER TABLE storage_deletions ADD CONSTRAINT fixture_reject_claim CHECK (false)");
        Assert.Equal(HttpStatusCode.InternalServerError, (await Delete(client)).StatusCode);
        Assert.Equal(0, factory.Cloud.Deletes);
        await using var verification = CreateContext();
        Assert.Empty(await verification.StorageDeletions.ToListAsync());
        Assert.Empty(await verification.StorageDeletionAttempts.ToListAsync());
        Assert.Single(await verification.Resources.ToListAsync());
        Assert.Single(await verification.ResourceConfigurations.ToListAsync());
        Assert.Single(await verification.StorageDeployments.ToListAsync());
    }
    [PostgreSqlFact]
    public async Task Cleanup_failure_rolls_back_locally_and_fresh_api_reconciles_absence_without_second_delete()
    {
        var cloud = new RecordingBucketProvider();
        using (var factory = Factory(cloud)) {
            using var client = Client(factory);
            await Seed(client);
            await using (var db = CreateContext()) {
                await db.Database.ExecuteSqlRawAsync("""
                    CREATE FUNCTION fixture_reject_delete() RETURNS trigger LANGUAGE plpgsql AS $$
                    BEGIN RAISE EXCEPTION 'fixture rejects local cleanup'; END; $$;
                    CREATE TRIGGER fixture_reject_delete BEFORE DELETE ON resources FOR EACH ROW EXECUTE FUNCTION fixture_reject_delete();
                    """);
            }
            Assert.Equal(HttpStatusCode.InternalServerError, (await Delete(client)).StatusCode);
        }
        await using (var db = CreateContext()) {
            Assert.Single(await db.Resources.ToListAsync());
            Assert.Single(await db.ResourceConfigurations.ToListAsync());
            Assert.Single(await db.StorageDeployments.ToListAsync());
            Assert.Single(await db.StorageDeploymentAttempts.ToListAsync());
            var receipt = await db.StorageDeletions.SingleAsync();
            Assert.Equal("pending", receipt.Status);
            receipt.LeaseUntilUtc = DateTime.UtcNow.AddMinutes(-1);
            await db.Database.ExecuteSqlRawAsync("DROP TRIGGER fixture_reject_delete ON resources");
            await db.SaveChangesAsync();
        }
        using var freshFactory = Factory(cloud); using var freshClient = Client(freshFactory);
        Assert.Equal("unknown", await Status(await freshClient.GetAsync(Route)));
        Assert.Equal("succeeded", await Status(await freshClient.PostAsync(Route + "/reconcile", null)));
        Assert.Equal(1, cloud.Deletes);
        Assert.Equal(1, cloud.DeletionInspections);
        await using var verification = CreateContext();
        Assert.Empty(await verification.Resources.ToListAsync());
        Assert.Empty(await verification.ResourceConfigurations.ToListAsync());
        Assert.Empty(await verification.StorageDeployments.ToListAsync());
        Assert.Empty(await verification.StorageDeploymentAttempts.ToListAsync());
        Assert.Equal("succeeded", (await verification.StorageDeletions.SingleAsync()).Status);
    }
    [PostgreSqlFact]
    public async Task Concurrent_duplicates_and_resource_writes_cannot_dispatch_twice_or_retarget_deletion()
    {
        using var factory = Factory(); using var client = Client(factory);
        await Seed(client);
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        factory.Cloud.BeforeDelete = async () => { entered.TrySetResult(); await release.Task.WaitAsync(TimeSpan.FromSeconds(20)); };
        var deleting = Delete(client);
        try {
            await entered.Task.WaitAsync(TimeSpan.FromSeconds(15));
            Assert.Equal(HttpStatusCode.Accepted, (await Delete(client)).StatusCode);
            Assert.Equal(HttpStatusCode.Accepted, (await client.PostAsync(Route + "/reconcile", null)).StatusCode);
            Assert.Equal(HttpStatusCode.Conflict, (await client.PutAsJsonAsync($"/resources/{_resource}", new { name = "Moved", type = "gcp.storage.bucket", x = 1 })).StatusCode);
            Assert.Equal(HttpStatusCode.Conflict, (await client.DeleteAsync($"/designs/{LegacyDesign.Id}")).StatusCode);
            Assert.Equal(1, factory.Cloud.Deletes);
        } finally { release.TrySetResult(); }
        Assert.Equal("succeeded", await Status(await deleting));
        Assert.Equal(1, factory.Cloud.Deletes);
        Assert.Equal(0, factory.Cloud.DeletionInspections);
    }
}
