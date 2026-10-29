using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;
using Blacksmith.Application.Interfaces;
using CloudServices.Core;
using Google;
using Google.Apis.Auth.OAuth2;
using Google.Apis.Storage.v1.Data;
using Google.Cloud.Storage.V1;

namespace Providers.GoogleCloud;

/// ADC is lazy: metadata CRUD and disabled deployment never read credentials.
public class GoogleCloudStorageService : ICloudStorageService, ICloudBucketProvisioner, ICloudBucketDeleter
{
    private readonly Lazy<GoogleCredential> _credential = new(() => GoogleCredential.GetApplicationDefault()
        .CreateScoped("https://www.googleapis.com/auth/cloud-platform"));
    private readonly Lazy<StorageClient> _client;
    private readonly Func<string, CancellationToken, Task<string?>>? _projectResolver;
    public GoogleCloudStorageService(StorageClient client, Func<string, CancellationToken, Task<string?>> projectResolver)
    {
        _client = new(() => client);
        _projectResolver = projectResolver;
    }
    public GoogleCloudStorageService() => _client = new(() => StorageClient.Create(_credential.Value));

    public Task<string> CreateBucketAsync(string projectId, string bucketName) =>
        Task.FromException<string>(new NotSupportedException("Unbound legacy provisioning is disabled."));

    public static Bucket BuildBucket(CloudBucketTarget target, string marker) => new()
    {
        Name = target.BucketName, Location = target.Location, StorageClass = "STANDARD",
        Labels = new Dictionary<string, string> {
            ["blacksmith-resource"] = target.ResourceId.ToString("N"), ["blacksmith-owner"] = marker
        },
        IamConfiguration = new Bucket.IamConfigurationData {
            PublicAccessPrevention = "enforced",
            UniformBucketLevelAccess = new Bucket.IamConfigurationData.UniformBucketLevelAccessData { Enabled = true }
        }
    };

    public Task<CloudBucketResult> EnsureAsync(CloudBucketTarget target, string marker, CancellationToken ct) =>
        ExecuteAsync(target, marker, create: true, ct);
    public Task<CloudBucketResult> InspectAsync(CloudBucketTarget target, string marker, CancellationToken ct) =>
        ExecuteAsync(target, marker, create: false, ct);

    private async Task<CloudBucketResult> ExecuteAsync(CloudBucketTarget target, string marker, bool create, CancellationToken ct)
    {
        var writeMayHaveHappened = false;
        try
        {
            // Resolve the configured project independently before any mutation.
            var projectNumber = await (_projectResolver is null ? ResolveProjectNumberAsync(target.ProjectId, ct) : _projectResolver(target.ProjectId, ct));
            if (projectNumber is null) return new(create ? "failed" : "unknown", "project_identity_unverified");
            Bucket? bucket;
            try { bucket = await FindBucketAsync(target.BucketName, ct); }
            catch (GoogleApiException error) when (!create && error.HttpStatusCode == HttpStatusCode.Forbidden)
            {
                // Read-only recovery may confirm absence even when metadata GET is forbidden.
                try {
                    await foreach (var candidate in _client.Value.ListBucketsAsync(target.ProjectId).WithCancellation(ct))
                        if (candidate.Name == target.BucketName) return new("unknown", "provider_access_failed");
                    return new("failed", "not_created");
                }
                catch (GoogleApiException) { return new("unknown", "bucket_absence_unverified"); }
            }
            if (bucket is null)
            {
                if (!create) return new("unknown", "bucket_not_found");
                writeMayHaveHappened = true;
                try
                {
                    await _client.Value.CreateBucketAsync(target.ProjectId, BuildBucket(target, marker), new CreateBucketOptions { RetryOptions = RetryOptions.Never }, cancellationToken: ct);
                }
                catch (GoogleApiException error) when (error.HttpStatusCode is HttpStatusCode.BadRequest or
                    HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden or HttpStatusCode.NotFound)
                { return new("failed", "provider_rejected"); }
                catch (GoogleApiException error) when (error.HttpStatusCode == HttpStatusCode.Conflict)
                { /* A name conflict never establishes ownership; verify the marker below. */ }
                bucket = await FindBucketAsync(target.BucketName, ct);
                if (bucket is null) return new("unknown", "bucket_not_observed");
            }
            return Verify(bucket, target, marker, projectNumber);
        }
        catch (GoogleApiException) { return new(!create || writeMayHaveHappened ? "unknown" : "failed", "provider_access_failed"); }
        catch (OperationCanceledException) { return new("unknown", "provider_timeout"); }
        catch (HttpRequestException) { return new("unknown", "provider_unavailable"); }
        catch (Exception) { return new(!create || writeMayHaveHappened ? "unknown" : "failed", "credentials_or_provider_unavailable"); }
    }

    public Task<CloudBucketResult> DeleteEmptyAsync(CloudBucketTarget target, string marker, CancellationToken ct) =>
        DeleteOrInspectAsync(target, marker, inspectOnly: false, ct);
    public Task<CloudBucketResult> InspectDeletionAsync(CloudBucketTarget target, string marker, CancellationToken ct) =>
        DeleteOrInspectAsync(target, marker, inspectOnly: true, ct);

    private async Task<CloudBucketResult> DeleteOrInspectAsync(CloudBucketTarget target, string marker, bool inspectOnly, CancellationToken ct)
    {
        try
        {
            var project = await (_projectResolver is null ? ResolveProjectNumberAsync(target.ProjectId, ct) : _projectResolver(target.ProjectId, ct));
            if (project is null) return new("failed", "project_identity_unverified");
            Bucket? bucket;
            try { bucket = await FindBucketAsync(target.BucketName, ct); }
            catch (GoogleApiException error) when (error.HttpStatusCode == HttpStatusCode.Forbidden)
            {
                // A bucket GET can return 403 even after deletion. Only a complete,
                // successful project listing establishes absence; never delete a bucket here.
                try
                {
                    await foreach (var candidate in _client.Value.ListBucketsAsync(target.ProjectId).WithCancellation(ct))
                        if (candidate.Name == target.BucketName) return new("failed", "provider_rejected");
                    return new("succeeded", "bucket_absent");
                }
                catch (GoogleApiException) { return new("unknown", "bucket_absence_unverified"); }
            }
            if (bucket is null) return new("succeeded", "bucket_absent");
            var verified = Verify(bucket, target, marker, project);
            if (verified.Status != "succeeded") return verified;
            if (inspectOnly) return new("failed", "bucket_still_exists");
            if (bucket.Metageneration is not > 0) return new("failed", "remote_identity_unverified");
            // No recursive delete, object enumeration or automatic retry. Google enforces emptiness.
            await _client.Value.DeleteBucketAsync(target.BucketName, new DeleteBucketOptions {
                IfMetagenerationMatch = bucket.Metageneration, DeleteObjects = false, RetryOptions = RetryOptions.Never
            }, ct);
            return new("succeeded", "bucket_deleted");
        }
        catch (GoogleApiException error) when (error.HttpStatusCode == HttpStatusCode.NotFound)
        { return new("succeeded", "bucket_absent"); }
        catch (GoogleApiException error) when (error.HttpStatusCode == HttpStatusCode.Conflict)
        { return new("failed", "bucket_not_empty"); }
        catch (GoogleApiException error) when (error.HttpStatusCode == HttpStatusCode.PreconditionFailed)
        { return new("failed", "remote_changed"); }
        catch (GoogleApiException error) when (error.HttpStatusCode is HttpStatusCode.Forbidden or HttpStatusCode.Unauthorized or HttpStatusCode.BadRequest)
        { return new("failed", "provider_rejected"); }
        catch (OperationCanceledException) { return new("unknown", "provider_timeout"); }
        catch (Exception) { return new("unknown", "provider_unconfirmed"); }
    }

    private async Task<Bucket?> FindBucketAsync(string name, CancellationToken ct)
    {
        try { return await _client.Value.GetBucketAsync(name, cancellationToken: ct); }
        catch (GoogleApiException error) when (error.HttpStatusCode == HttpStatusCode.NotFound) { return null; }
    }

    private async Task<string?> ResolveProjectNumberAsync(string projectId, CancellationToken ct)
    {
        var token = await ((ITokenAccess)_credential.Value).GetAccessTokenForRequestAsync(cancellationToken: ct);
        using var client = new HttpClient();
        using var request = new HttpRequestMessage(HttpMethod.Get,
            $"https://cloudresourcemanager.googleapis.com/v1/projects/{Uri.EscapeDataString(projectId)}");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        using var response = await client.SendAsync(request, ct);
        if (!response.IsSuccessStatusCode) return null;
        using var data = JsonDocument.Parse(await response.Content.ReadAsStringAsync(ct));
        var root = data.RootElement;
        if (root.GetProperty("projectId").GetString() != projectId || root.GetProperty("lifecycleState").GetString() != "ACTIVE") return null;
        var number = root.GetProperty("projectNumber").GetString();
        return number is not null && number.All(char.IsAsciiDigit) && number.Length > 0 ? number : null;
    }

    public static CloudBucketResult Verify(Bucket bucket, CloudBucketTarget target, string marker, string projectNumber)
    {
        if (bucket.Name != target.BucketName || bucket.ProjectNumber?.ToString() != projectNumber ||
            bucket.Labels is null || !bucket.Labels.TryGetValue("blacksmith-resource", out var resource) ||
            resource != target.ResourceId.ToString("N") || !bucket.Labels.TryGetValue("blacksmith-owner", out var owner) || owner != marker)
            return new("failed", "unrelated_bucket");
        if (!string.Equals(bucket.Location, target.Location, StringComparison.OrdinalIgnoreCase) ||
            !string.Equals(bucket.StorageClass, "STANDARD", StringComparison.OrdinalIgnoreCase) ||
            bucket.IamConfiguration?.UniformBucketLevelAccess?.Enabled != true ||
            bucket.IamConfiguration?.PublicAccessPrevention != "enforced")
            return new("failed", "remote_settings_mismatch");
        return new("succeeded", "verified", new(projectNumber, bucket.Id ?? bucket.Name, bucket.Metageneration?.ToString() ?? ""));
    }
}
