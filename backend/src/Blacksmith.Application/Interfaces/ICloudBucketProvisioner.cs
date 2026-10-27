namespace Blacksmith.Application.Interfaces;

public sealed record CloudBucketTarget(Guid ResourceId, string ProjectId, string BucketName, string Location);
public sealed record CloudBucketIdentity(string ProjectNumber, string BucketId, string Metageneration);
public sealed record CloudBucketResult(string Status, string Code, CloudBucketIdentity? Identity = null);

/// Google SDK/HTTP implementation belongs to the provider; no delete/compensation.
public interface ICloudBucketProvisioner
{
    Task<CloudBucketResult> EnsureAsync(CloudBucketTarget target, string ownershipMarker, CancellationToken ct);
    Task<CloudBucketResult> InspectAsync(CloudBucketTarget target, string ownershipMarker, CancellationToken ct);
}
