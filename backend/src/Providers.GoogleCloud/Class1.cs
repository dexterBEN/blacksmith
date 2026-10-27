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
public class GoogleCloudStorageService : ICloudStorageService, ICloudBucketProvisioner
{
    private readonly Lazy<GoogleCredential> _credential = new(() => GoogleCredential.GetApplicationDefault()
        .CreateScoped("https://www.googleapis.com/auth/cloud-platform"));
    private readonly Lazy<StorageClient> _client;
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
            var projectNumber = await ResolveProjectNumberAsync(target.ProjectId, ct);
            if (projectNumber is null) return new(create ? "failed" : "unknown", "project_identity_unverified");
            var bucket = await FindBucketAsync(target.BucketName, ct);
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
