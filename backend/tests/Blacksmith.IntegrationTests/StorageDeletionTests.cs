using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Blacksmith.Infrastructure.Persistence;
using Blacksmith.TestSupport;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace Blacksmith.IntegrationTests;

public sealed class StorageDeletionTests : IDisposable
{
    private readonly SqliteConnection _connection = new("Data Source=:memory:");
    private readonly DeploymentApiFactory _factory;
    private readonly HttpClient _client;
    private readonly Guid _design = Guid.NewGuid(), _resource = Guid.NewGuid(), _operation = Guid.NewGuid();
    private string Route(Guid? operation = null) => $"/designs/{_design}/resources/{_resource}/deletions/{operation ?? _operation}";
    public StorageDeletionTests()
    {
        _connection.Open();
        _factory = new(o => o.UseSqlite(_connection));
        _client = _factory.CreateClient(new WebApplicationFactoryClientOptions { BaseAddress = new("https://localhost") });
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<BlacksmithDbContext>();
        db.Database.EnsureCreated();
        db.Designs.Add(new() { Id = _design, Name = "Delete fixture" });
        db.SaveChanges();
    }
    private async Task Deploy()
    {
        using var request = new HttpRequestMessage(HttpMethod.Put, $"/designs/{_design}/resources/{_resource}/deployments/{Guid.NewGuid()}") {
            Content = JsonContent.Create(StorageDeploymentTests.Body())
        };
        request.Headers.TryAddWithoutValidation("If-None-Match", "*");
        request.Headers.Add("X-Blacksmith-Deploy-Consent", "true");
        Assert.Equal(HttpStatusCode.OK, (await _client.SendAsync(request)).StatusCode);
    }
    private Task<HttpResponseMessage> Command(string? route = null, bool consent = true, long? revision = 1, HttpMethod? method = null, HttpClient? client = null)
    {
        var request = new HttpRequestMessage(method ?? HttpMethod.Put, route ?? Route());
        var target = Guid.Parse((route ?? Route()).Split('/')[4]);
        if (consent) request.Headers.Add("X-Blacksmith-Delete-Consent", "true");
        if (revision is not null) request.Headers.TryAddWithoutValidation("If-Match", $"\"resource-{target:N}-r{revision}\"");
        return (client ?? _client).SendAsync(request);
    }
    private static async Task<string> Status(HttpResponseMessage response, string field = "status")
    {
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        return (await response.Content.ReadFromJsonAsync<JsonElement>()).GetProperty(field).GetString()!;
    }
    private async Task AssertLocal(bool present)
    {
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<BlacksmithDbContext>();
        Assert.Equal(present, await db.Resources.AnyAsync(x => x.Id == _resource));
        Assert.Equal(present, await db.ResourceConfigurations.AnyAsync(x => x.ResourceId == _resource));
        Assert.Equal(present, await db.StorageDeployments.AnyAsync(x => x.ResourceId == _resource));
        Assert.Equal(present, await db.StorageDeploymentAttempts.AnyAsync());
        Assert.Single(await db.Designs.ToListAsync());
        Assert.Equal(6, await db.ResourceTypes.CountAsync());
    }
    [Fact]
    public async Task Explicit_delete_commits_receipt_before_cloud_and_cleans_only_local_aggregate()
    {
        await Deploy();
        _factory.Cloud.BeforeDelete = async () => {
            using var scope = _factory.Services.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<BlacksmithDbContext>();
            Assert.Equal("pending", (await db.StorageDeletions.SingleAsync()).Status);
            await AssertLocal(true);
        };
        Assert.Equal("succeeded", await Status(await Command()));
        await AssertLocal(false);
        Assert.Equal(0, _factory.Cloud.Buckets);
        Assert.Equal(1, _factory.Cloud.Deletes);
        Assert.Equal("succeeded", await Status(await Command()));
        Assert.Equal("succeeded", await Status(await _client.GetAsync(Route())));
        Assert.Equal(1, _factory.Cloud.Deletes);
        Assert.Equal(HttpStatusCode.NoContent, (await _client.DeleteAsync($"/designs/{_design}")).StatusCode);
        Assert.Equal("succeeded", await Status(await _client.GetAsync(Route())));
    }
    [Theory]
    [InlineData(false, 1, 400)]
    [InlineData(true, 0, 428)]
    [InlineData(true, 2, 412)]
    public async Task Consent_and_revision_are_required_before_any_mutation(bool consent, long revision, int expected)
    {
        await Deploy();
        Assert.Equal(expected, (int)(await Command(consent: consent, revision: revision == 0 ? null : revision)).StatusCode);
        await AssertLocal(true);
        Assert.Equal(0, _factory.Cloud.Deletes);
        using var scope = _factory.Services.CreateScope();
        Assert.Empty(await scope.ServiceProvider.GetRequiredService<BlacksmithDbContext>().StorageDeletions.ToListAsync());
    }
    [Theory]
    [InlineData("bucket_not_empty")]
    [InlineData("provider_rejected")]
    [InlineData("unrelated_bucket")]
    [InlineData("remote_changed")]
    public async Task Provider_rejection_preserves_recovery_data_and_explicit_retry_is_deduplicated(string code)
    {
        await Deploy();
        _factory.Cloud.DeleteFailure = code;
        Assert.Equal("failed", await Status(await Command()));
        await AssertLocal(true);
        Assert.Equal(code, await Status(await _client.GetAsync(Route()), "code"));
        Assert.Equal("failed", await Status(await Command()));
        Assert.Equal(1, _factory.Cloud.Deletes);
        _factory.Cloud.DeleteFailure = null;
        var retry = Route() + $"/retry/{Guid.NewGuid()}";
        Assert.Equal("succeeded", await Status(await Command(retry, method: HttpMethod.Post)));
        Assert.Equal("succeeded", await Status(await Command(retry, method: HttpMethod.Post)));
        Assert.Equal(2, _factory.Cloud.Deletes);
        await AssertLocal(false);
    }
    [Fact]
    public async Task Lost_response_is_reconciled_read_only_after_fresh_client_without_another_delete()
    {
        await Deploy();
        _factory.Cloud.LoseDeleteResponse = true;
        Assert.Equal("unknown", await Status(await Command()));
        await AssertLocal(true);
        Assert.Equal("unknown", await Status(await Command()));
        Assert.Equal(HttpStatusCode.Conflict, (await Command(Route() + $"/retry/{Guid.NewGuid()}", method: HttpMethod.Post)).StatusCode);
        using var fresh = _factory.CreateClient(new WebApplicationFactoryClientOptions { BaseAddress = new("https://localhost") });
        Assert.Equal("unknown", await Status(await fresh.GetAsync(Route())));
        Assert.Equal("succeeded", await Status(await fresh.PostAsync(Route() + "/reconcile", null)));
        await AssertLocal(false);
        Assert.Equal(1, _factory.Cloud.Deletes);
        Assert.Equal(1, _factory.Cloud.DeletionInspections);
    }
    [Fact]
    public async Task Interrupted_claim_requires_reconciliation_and_present_bucket_requires_deliberate_retry()
    {
        await Deploy();
        _factory.Cloud.DeleteFailure = "provider_rejected";
        await Command();
        using (var scope = _factory.Services.CreateScope()) {
            var db = scope.ServiceProvider.GetRequiredService<BlacksmithDbContext>();
            var deletion = await db.StorageDeletions.SingleAsync();
            deletion.Status = "pending";
            deletion.LeaseUntilUtc = DateTime.UtcNow.AddMinutes(-1);
            await db.SaveChangesAsync();
        }
        Assert.Equal("unknown", await Status(await _client.GetAsync(Route())));
        Assert.Equal("failed", await Status(await _client.PostAsync(Route() + "/reconcile", null)));
        Assert.Equal("bucket_still_exists", await Status(await _client.GetAsync(Route()), "code"));
        await AssertLocal(true);
        Assert.Equal(1, _factory.Cloud.Deletes);
    }
    [Fact]
    public async Task Deletion_freezes_all_resource_writes_and_deployment_replays()
    {
        await Deploy();
        _factory.Cloud.DeleteFailure = "bucket_not_empty";
        await Command();
        Assert.Equal(HttpStatusCode.Conflict, (await _client.PutAsJsonAsync($"/resources/{_resource}", new { name = "Changed", type = "gcp.storage.bucket" })).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await _client.DeleteAsync($"/resources/{_resource}")).StatusCode);
        using var request = new HttpRequestMessage(HttpMethod.Put, $"/designs/{_design}/resources/{_resource}/deployments/{Guid.NewGuid()}") {
            Content = JsonContent.Create(StorageDeploymentTests.Body())
        };
        request.Headers.Add("X-Blacksmith-Deploy-Consent", "true");
        request.Headers.TryAddWithoutValidation("If-Match", $"\"resource-{_resource:N}-r1\"");
        Assert.Equal(HttpStatusCode.Conflict, (await _client.SendAsync(request)).StatusCode);
        Assert.Equal(1, _factory.Cloud.Creates);
        await AssertLocal(true);
    }
    [Fact]
    public async Task Wrong_scope_unknown_resource_and_different_operation_never_delete()
    {
        await Deploy();
        Assert.Equal(HttpStatusCode.NotFound, (await Command(Route().Replace(_design.ToString(), Guid.NewGuid().ToString()))).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await Command(Route().Replace(_resource.ToString(), Guid.NewGuid().ToString()))).StatusCode);
        Assert.Equal(0, _factory.Cloud.Deletes);
        await Command();
        Assert.Equal(HttpStatusCode.NotFound, (await Command(Route(Guid.NewGuid()))).StatusCode);
        Assert.Equal(1, _factory.Cloud.Deletes);
    }
    [Theory]
    [InlineData("pending")]
    [InlineData("unknown")]
    public async Task Outstanding_deployment_blocks_deletion(string status)
    {
        await Deploy();
        using (var scope = _factory.Services.CreateScope()) {
            var db = scope.ServiceProvider.GetRequiredService<BlacksmithDbContext>();
            (await db.StorageDeployments.SingleAsync()).Status = status;
            await db.SaveChangesAsync();
        }
        Assert.Equal(HttpStatusCode.Conflict, (await Command()).StatusCode);
        Assert.Equal(0, _factory.Cloud.Deletes);
        await AssertLocal(true);
    }
    [Theory]
    [InlineData("Development", false)]
    [InlineData("Production", true)]
    public async Task Disabled_policy_blocks_remote_deletion(string environment, bool enabled)
    {
        await Deploy();
        using var factory = new DeploymentApiFactory(o => o.UseSqlite(_connection), environment, enabled);
        using var client = factory.CreateClient(new WebApplicationFactoryClientOptions { BaseAddress = new("https://localhost") });
        Assert.Equal(HttpStatusCode.Forbidden, (await Command(client: client)).StatusCode);
        Assert.Equal(0, factory.Cloud.Deletes);
        await AssertLocal(true);
    }
    [Fact]
    public async Task Unapproved_project_is_rejected_before_claim_or_cloud_call()
    {
        await Deploy();
        using (var scope = _factory.Services.CreateScope()) {
            var db = scope.ServiceProvider.GetRequiredService<BlacksmithDbContext>();
            (await db.StorageDeployments.SingleAsync()).ProjectId = "other-project-123";
            await db.SaveChangesAsync();
        }
        Assert.Equal(HttpStatusCode.Forbidden, (await Command()).StatusCode);
        Assert.Equal(0, _factory.Cloud.Deletes);
        await AssertLocal(true);
    }
    [Fact]
    public async Task Save_only_retarget_does_not_change_frozen_cloud_deletion_target()
    {
        await Deploy();
        var update = await _client.PutAsJsonAsync($"/resources/{_resource}/configuration", new {
            schemaVersion = 1, configuration = new { projectId = "example-project-123", bucketName = "another-bucket", location = "europe-west9" }
        });
        Assert.Equal(HttpStatusCode.OK, update.StatusCode);
        Assert.Equal("succeeded", await Status(await Command(revision: 2)));
        Assert.Equal(0, _factory.Cloud.Buckets);
        Assert.Equal(1, _factory.Cloud.Deletes);
        await AssertLocal(false);
    }
    public void Dispose() { _client.Dispose(); _factory.Dispose(); _connection.Dispose(); }
}
