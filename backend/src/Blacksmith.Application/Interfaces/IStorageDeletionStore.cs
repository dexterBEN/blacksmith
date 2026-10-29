using Blacksmith.Domain.Entities;

namespace Blacksmith.Application.Interfaces;

public interface IStorageDeletionStore
{
    Task<StorageDeletion?> FindDeletionAsync(Guid resourceId, CancellationToken ct);
    Task<ResourceEntity?> DeletionResourceAsync(Guid resourceId, CancellationToken ct);
    Task<bool> HasDeletionAttemptAsync(Guid requestId, CancellationToken ct);
    void AddDeletion(StorageDeletion deletion);
    void AddDeletionAttempt(StorageDeletionAttempt attempt);
    Task RemoveDeletedResourceAsync(Guid resourceId, CancellationToken ct);
}

public interface ICloudBucketDeleter
{
    // Only an owned empty bucket may be deleted. InspectDeletion never mutates Google.
    Task<CloudBucketResult> DeleteEmptyAsync(CloudBucketTarget target, string marker, CancellationToken ct);
    Task<CloudBucketResult> InspectDeletionAsync(CloudBucketTarget target, string marker, CancellationToken ct);
}
