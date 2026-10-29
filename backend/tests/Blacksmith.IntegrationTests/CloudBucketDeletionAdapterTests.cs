using System.Net;
using Blacksmith.Application.Interfaces;
using Google;
using Google.Apis.Storage.v1.Data;
using Google.Cloud.Storage.V1;
using Providers.GoogleCloud;
using Xunit;

namespace Blacksmith.IntegrationTests;

public sealed class CloudBucketDeletionAdapterTests
{
    private readonly CloudBucketTarget _target = new(Guid.NewGuid(), "example-project-123", "blacksmith-fixture", "europe-west9");
    private const string Marker = "fixture-marker";
    private const string Project = "123456789";
    private Bucket Owned()
    {
        var bucket = GoogleCloudStorageService.BuildBucket(_target, Marker);
        bucket.ProjectNumber = ulong.Parse(Project);
        bucket.Metageneration = 7;
        return bucket;
    }
    [Fact]
    public async Task Empty_bucket_delete_is_conditional_nonrecursive_and_disables_sdk_retries()
    {
        var client = new StubStorage { Bucket = Owned() };
        var provider = new GoogleCloudStorageService(client, (_, _) => Task.FromResult<string?>(Project));
        Assert.Equal("bucket_deleted", (await provider.DeleteEmptyAsync(_target, Marker, default)).Code);
        Assert.Equal(1, client.Deletes);
        Assert.Equal(7, client.Options!.IfMetagenerationMatch);
        Assert.False(client.Options.DeleteObjects);
        Assert.Same(RetryOptions.Never, client.Options.RetryOptions);
    }
    [Theory]
    [InlineData("owner")]
    [InlineData("resource")]
    [InlineData("project")]
    [InlineData("location")]
    [InlineData("metageneration")]
    public async Task Unverified_bucket_is_never_deleted(string mismatch)
    {
        var bucket = Owned();
        switch (mismatch) {
            case "owner": bucket.Labels["blacksmith-owner"] = "other"; break;
            case "resource": bucket.Labels["blacksmith-resource"] = Guid.NewGuid().ToString("N"); break;
            case "project": bucket.ProjectNumber = 42; break;
            case "location": bucket.Location = "us-central1"; break;
            case "metageneration": bucket.Metageneration = null; break;
        }
        var client = new StubStorage { Bucket = bucket };
        var provider = new GoogleCloudStorageService(client, (_, _) => Task.FromResult<string?>(Project));
        Assert.Equal("failed", (await provider.DeleteEmptyAsync(_target, Marker, default)).Status);
        Assert.Equal(0, client.Deletes);
    }
    [Theory]
    [InlineData(409, "failed", "bucket_not_empty")]
    [InlineData(403, "failed", "provider_rejected")]
    [InlineData(412, "failed", "remote_changed")]
    [InlineData(404, "succeeded", "bucket_absent")]
    [InlineData(503, "unknown", "provider_unconfirmed")]
    public async Task Delete_errors_have_explicit_outcomes_and_never_repeat(int http, string status, string code)
    {
        var client = new StubStorage { Bucket = Owned(), DeleteError = new GoogleApiException("storage", "fixture") { HttpStatusCode = (HttpStatusCode)http } };
        var provider = new GoogleCloudStorageService(client, (_, _) => Task.FromResult<string?>(Project));
        var result = await provider.DeleteEmptyAsync(_target, Marker, default);
        Assert.Equal(status, result.Status);
        Assert.Equal(code, result.Code);
        Assert.Equal(1, client.Deletes);
    }
    [Fact]
    public async Task Absence_completes_and_reconciliation_is_read_only()
    {
        var client = new StubStorage();
        var provider = new GoogleCloudStorageService(client, (_, _) => Task.FromResult<string?>(Project));
        Assert.Equal("bucket_absent", (await provider.DeleteEmptyAsync(_target, Marker, default)).Code);
        Assert.Equal("bucket_absent", (await provider.InspectDeletionAsync(_target, Marker, default)).Code);
        client.Bucket = Owned();
        Assert.Equal("bucket_still_exists", (await provider.InspectDeletionAsync(_target, Marker, default)).Code);
        Assert.Equal(0, client.Deletes);
    }
    [Fact]
    public async Task Unresolved_project_and_network_timeout_preserve_local_recovery()
    {
        var client = new StubStorage { Bucket = Owned() };
        var provider = new GoogleCloudStorageService(client, (_, _) => Task.FromResult<string?>(null));
        Assert.Equal("failed", (await provider.DeleteEmptyAsync(_target, Marker, default)).Status);
        Assert.Equal(0, client.Deletes);
        provider = new GoogleCloudStorageService(client, (_, _) => Task.FromResult<string?>(Project));
        client.DeleteError = new OperationCanceledException();
        Assert.Equal("unknown", (await provider.DeleteEmptyAsync(_target, Marker, default)).Status);
    }
    private sealed class StubStorage : StorageClient
    {
        public Bucket? Bucket { get; set; }
        public Exception? DeleteError { get; set; }
        public int Deletes { get; private set; }
        public DeleteBucketOptions? Options { get; private set; }
        public override Task<Bucket> GetBucketAsync(string bucket, GetBucketOptions? options = null, CancellationToken cancellationToken = default) =>
            Bucket is null ? Task.FromException<Bucket>(new GoogleApiException("storage", "fixture") { HttpStatusCode = HttpStatusCode.NotFound }) : Task.FromResult(Bucket);
        public override Task DeleteBucketAsync(string bucket, DeleteBucketOptions? options = null, CancellationToken cancellationToken = default)
        {
            Deletes++;
            Options = options;
            return DeleteError is null ? Task.CompletedTask : Task.FromException(DeleteError);
        }
    }
}
