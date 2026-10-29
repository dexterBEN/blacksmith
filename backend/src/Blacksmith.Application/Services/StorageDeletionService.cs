using Blacksmith.Application.DTOs;
using Blacksmith.Application.Exceptions;
using Blacksmith.Application.Interfaces;
using Blacksmith.Application.Validation;
using Blacksmith.Domain.Entities;

namespace Blacksmith.Application.Services;

public sealed class StorageDeletionService(IStorageDeploymentStore locks, IStorageDeletionStore store,
    ICloudBucketDeleter cloud, IDeploymentTargetPolicy policy) : IStorageDeletionService
{
    public async Task<StorageDeletionResponse> DeleteAsync(Guid designId, Guid resourceId, Guid operationId,
        long revision, CancellationToken ct)
    {
        Validate(designId, resourceId, operationId);
        await using (var transaction = await locks.LockResourceAsync(resourceId, ct))
        {
            var previous = await store.FindDeletionAsync(resourceId, ct);
            if (previous is not null) return Scope(previous, designId, operationId);
            var resource = await store.DeletionResourceAsync(resourceId, ct)
                ?? throw Error("resource_not_found", "Resource not found.", 404);
            if (resource.DesignId != designId) throw Error("resource_not_found", "Resource not found in this Design.", 404);
            if (resource.Revision != revision) throw Error("revision_conflict", "Read the current Resource revision before deletion.", 412);
            if (resource.Type != CloudStorageConfigurationV1.ResourceType)
                throw Error("unsupported_resource", "Only deployed Cloud Storage resources support bucket deletion.", 400);
            var binding = resource.Deployments.OrderBy(x => x.CreatedAtUtc).ThenBy(x => x.Id).FirstOrDefault()
                ?? throw Error("deployment_required", "Use local Resource DELETE for an undeployed resource.");
            if (resource.Deployments.Any(x => x.Status is "pending" or "unknown"))
                throw Error("deployment_unresolved", "Resolve every outstanding deployment before deleting its bucket.");
            // The frozen deployment target is authoritative even if Save-only changed the current JSON.
            if (resource.Deployments.Any(x => x.DesignId != designId || x.ProjectId != binding.ProjectId ||
                x.BucketName != binding.BucketName || x.Location != binding.Location || x.OwnershipMarker != binding.OwnershipMarker))
                throw Error("deployment_target_conflict", "Deployment targets do not identify one bucket.");
            policy.RequireApprovedProject(binding.ProjectId);
            if (await store.HasDeletionAttemptAsync(operationId, ct)) throw Error("request_id_reused", "Deletion request ID already exists.");
            var deletion = new StorageDeletion {
                Id = operationId, ResourceId = resourceId, DesignId = designId, ResourceRevision = revision,
                ProjectId = binding.ProjectId, BucketName = binding.BucketName, Location = binding.Location,
                OwnershipMarker = binding.OwnershipMarker, CurrentAttemptId = operationId,
                LeaseUntilUtc = DateTime.UtcNow.AddSeconds(45)
            };
            store.AddDeletion(deletion);
            store.AddDeletionAttempt(new() { Id = operationId, ResourceId = resourceId });
            await transaction.CommitAsync(ct);
        }
        return await ExecuteAsync(designId, resourceId, operationId, operationId, inspectOnly: false);
    }

    public async Task<StorageDeletionResponse> ReadAsync(Guid designId, Guid resourceId, Guid operationId, CancellationToken ct)
    {
        Validate(designId, resourceId, operationId);
        var deletion = await store.FindDeletionAsync(resourceId, ct)
            ?? throw Error("deletion_not_found", "Deletion operation not found.", 404);
        return Scope(deletion, designId, operationId);
    }

    public Task<StorageDeletionResponse> ReconcileAsync(Guid designId, Guid resourceId, Guid operationId, CancellationToken ct) =>
        ClaimAsync(designId, resourceId, operationId, Guid.NewGuid(), null, inspectOnly: true, ct);

    public Task<StorageDeletionResponse> RetryAsync(Guid designId, Guid resourceId, Guid operationId, Guid requestId,
        long revision, CancellationToken ct) =>
        ClaimAsync(designId, resourceId, operationId, requestId, revision, inspectOnly: false, ct);

    private async Task<StorageDeletionResponse> ClaimAsync(Guid designId, Guid resourceId, Guid operationId,
        Guid requestId, long? revision, bool inspectOnly, CancellationToken ct)
    {
        Validate(designId, resourceId, operationId, requestId);
        await using (var transaction = await locks.LockResourceAsync(resourceId, ct))
        {
            var deletion = await store.FindDeletionAsync(resourceId, ct)
                ?? throw Error("deletion_not_found", "Deletion operation not found.", 404);
            var response = Scope(deletion, designId, operationId);
            policy.RequireApprovedProject(deletion.ProjectId);
            if (deletion.Status == "succeeded") return response;
            if (await store.HasDeletionAttemptAsync(requestId, ct)) return response;
            if (deletion.Status == "pending" && deletion.LeaseUntilUtc > DateTime.UtcNow) return response;
            if (!inspectOnly && response.Status != "failed")
                throw Error("deletion_unresolved", "Reconcile the uncertain result before retrying deletion.");
            if (!inspectOnly && revision != deletion.ResourceRevision)
                throw Error("revision_conflict", "Use the deletion's frozen Resource revision.", 412);
            deletion.CurrentAttemptId = requestId;
            deletion.Status = "pending";
            deletion.Code = inspectOnly ? "checking_deletion" : "deleting";
            deletion.LeaseUntilUtc = DateTime.UtcNow.AddSeconds(45);
            deletion.UpdatedAtUtc = DateTime.UtcNow;
            deletion.Version++;
            store.AddDeletionAttempt(new() { Id = requestId, ResourceId = resourceId });
            await transaction.CommitAsync(ct);
        }
        return await ExecuteAsync(designId, resourceId, operationId, requestId, inspectOnly);
    }

    private async Task<StorageDeletionResponse> ExecuteAsync(Guid designId, Guid resourceId, Guid operationId,
        Guid attemptId, bool inspectOnly)
    {
        var frozen = await store.FindDeletionAsync(resourceId, CancellationToken.None)
            ?? throw Error("deletion_not_found", "Deletion operation not found.", 404);
        var target = new CloudBucketTarget(resourceId, frozen.ProjectId, frozen.BucketName, frozen.Location);
        CloudBucketResult result;
        using (var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(20)))
        {
            try {
                result = inspectOnly
                    ? await cloud.InspectDeletionAsync(target, frozen.OwnershipMarker, timeout.Token)
                    : await cloud.DeleteEmptyAsync(target, frozen.OwnershipMarker, timeout.Token);
            }
            catch (Exception) { result = new("unknown", "provider_unconfirmed"); }
        }
        // Only an explicit absence/deletion result permits destruction of local recovery information.
        if (result.Status is not ("succeeded" or "failed" or "unknown") ||
            result.Status == "succeeded" && result.Code is not ("bucket_deleted" or "bucket_absent") ||
            !System.Text.RegularExpressions.Regex.IsMatch(result.Code, "^[a-z_]{1,60}$"))
            result = new("unknown", "provider_protocol_error");
        await using var transaction = await locks.LockResourceAsync(resourceId, CancellationToken.None);
        var deletion = await store.FindDeletionAsync(resourceId, CancellationToken.None)
            ?? throw Error("deletion_not_found", "Deletion operation not found.", 404);
        Scope(deletion, designId, operationId);
        if (deletion.CurrentAttemptId != attemptId) return StorageDeletionResponse.From(deletion);
        deletion.Status = result.Status;
        deletion.Code = result.Code;
        deletion.LeaseUntilUtc = null;
        deletion.UpdatedAtUtc = DateTime.UtcNow;
        deletion.Version++;
        if (result.Status == "succeeded") await store.RemoveDeletedResourceAsync(resourceId, CancellationToken.None);
        // Receipt and cleanup commit together. Failure leaves the durable pending receipt for reconciliation.
        await transaction.CommitAsync(CancellationToken.None);
        return StorageDeletionResponse.From(deletion);
    }

    private static StorageDeletionResponse Scope(StorageDeletion deletion, Guid designId, Guid operationId)
    {
        if (deletion.DesignId != designId || deletion.Id != operationId)
            throw Error("deletion_not_found", "Deletion operation not found in this Resource.", 404);
        return StorageDeletionResponse.From(deletion);
    }
    private static void Validate(params Guid[] ids)
    {
        if (ids.Any(x => x == Guid.Empty)) throw Error("invalid_id", "Nonempty UUIDs are required.", 400);
    }
    private static ResourceConflictException Error(string code, string message, int status = 409) => new(code, message, status);
}
