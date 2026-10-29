using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Blacksmith.Application.DTOs;
using Blacksmith.Application.Exceptions;
using Blacksmith.Application.Interfaces;
using Blacksmith.Application.Validation;
using Blacksmith.Domain.Entities;

namespace Blacksmith.Application.Services;

/// Resource/configuration/intent commit first; external effects never belong to that transaction.
public sealed class StorageDeploymentService(IStorageDeploymentStore store, IResourceService resources,
    ICloudBucketProvisioner cloud, IDeploymentTargetPolicy policy, IStorageDeletionStore deletions) : IStorageDeploymentService
{
    public async Task<StorageDeploymentResult> SaveAndDeployAsync(Guid designId, Guid resourceId, Guid operationId,
        JsonElement body, bool createOnly, long? revision, CancellationToken ct)
    {
        Nonempty(designId, resourceId, operationId);
        var write = ConfiguredResourceWrite.Parse(body);
        var project = write.Configuration.GetProperty("projectId").GetString()!;
        policy.RequireApprovedProject(project); // Before even the database Save.
        var configurationHash = Hash(write.Configuration.GetRawText());
        var requestHash = Hash(JsonSerializer.Serialize(new { write.Name, write.Type, write.ResourceTypeId,
            write.X, write.Y, configuration = write.Configuration }));
        StorageDeployment operation;
        var execute = false;
        await using (var transaction = await store.LockResourceAsync(resourceId, ct))
        {
            await RequireNotDeleting(resourceId, ct);
            var existing = await store.FindAsync(operationId, ct);
            if (existing is not null)
            {
                Scope(existing, designId, resourceId);
                if (existing.RequestHash != requestHash)
                    throw Conflict("operation_id_reused", "The operation ID already belongs to a different intent.");
                operation = existing; // A replay does not repeat Save or its old precondition.
                execute = operation.Status == "pending" && operation.CurrentAttemptId is null;
            }
            else
            {
                var binding = await store.FirstForResourceAsync(resourceId, ct);
                if (binding is not null && binding.ConfigurationHash != configurationHash)
                    throw Conflict("deployment_target_locked", "This Resource already has a deployment intent for another configuration. Save-only remains available; retargeting is outside this increment.");
                var saved = await resources.WriteConfiguredAsync(designId, resourceId, body, createOnly, revision, ct);
                var sameRevision = await store.ForRevisionAsync(resourceId, saved.Resource.Revision, ct);
                if (sameRevision is not null)
                {
                    if (sameRevision.RequestHash != requestHash)
                        throw Conflict("deployment_revision_conflict", "The revision already has another deployment intent.");
                    operation = sameRevision;
                    execute = operation.Status == "pending" && operation.CurrentAttemptId is null;
                }
                else
                {
                    if (binding is not null && StorageDeploymentResponse.From(binding).Status is "pending" or "unknown")
                        throw Conflict("deployment_unresolved", "Reconcile the previous deployment before requesting another revision.");
                    operation = new StorageDeployment {
                        Id = operationId, ResourceId = resourceId, DesignId = designId,
                        ResourceRevision = saved.Resource.Revision, RequestHash = requestHash,
                        ConfigurationHash = configurationHash, Configuration = write.Configuration.GetRawText(),
                        OwnershipMarker = binding?.OwnershipMarker ?? Guid.NewGuid().ToString("N"),
                        ProjectId = project, BucketName = write.Configuration.GetProperty("bucketName").GetString()!,
                        Location = write.Configuration.GetProperty("location").GetString()!
                    };
                    store.Add(operation);
                    execute = true;
                }
            }
            // The resource writer participates in this outer transaction. No Google call before this commit.
            await transaction.CommitAsync(ct);
        }
        var outcome = execute
            ? await ExecuteAsync(designId, resourceId, operation.Id, operation.Id, inspectOnly: false)
            : StorageDeploymentResponse.From(operation);
        var aggregate = await resources.GetAggregateAsync(resourceId, CancellationToken.None)
            ?? throw Conflict("resource_not_found", "Saved Resource cannot currently be read.", 404);
        return new(aggregate, outcome);
    }

    public async Task<StorageDeploymentResponse> ReadAsync(Guid designId, Guid resourceId, Guid operationId, CancellationToken ct)
    {
        Nonempty(designId, resourceId, operationId);
        var operation = await store.FindAsync(operationId, ct)
            ?? throw Conflict("deployment_not_found", "Deployment operation not found.", 404);
        Scope(operation, designId, resourceId);
        return StorageDeploymentResponse.From(operation); // Metadata only, never Google.
    }

    public async Task<StorageDeploymentResponse> ReconcileAsync(Guid designId, Guid resourceId, Guid operationId, CancellationToken ct)
    {
        await ReadAsync(designId, resourceId, operationId, ct);
        return await ExecuteAsync(designId, resourceId, operationId, Guid.NewGuid(), inspectOnly: true);
    }

    public async Task<StorageDeploymentResponse> RetryAsync(Guid designId, Guid resourceId, Guid operationId,
        Guid requestId, long revision, CancellationToken ct)
    {
        Nonempty(designId, resourceId, operationId, requestId);
        var operation = await ReadAsync(designId, resourceId, operationId, ct);
        var resource = await resources.GetAggregateAsync(resourceId, ct)
            ?? throw Conflict("resource_not_found", "Resource not found.", 404);
        if (revision != resource.Revision || revision != operation.ResourceRevision)
            throw Conflict("revision_conflict", "Read the original Resource revision before retrying deployment.", 412);
        return await ExecuteAsync(designId, resourceId, operationId, requestId, inspectOnly: false, retry: true);
    }

    private async Task<StorageDeploymentResponse> ExecuteAsync(Guid designId, Guid resourceId, Guid id,
        Guid requestId, bool inspectOnly, bool retry = false)
    {
        CloudBucketTarget target;
        string marker, previousStatus;
        await using (var transaction = await store.LockResourceAsync(resourceId, CancellationToken.None))
        {
            await RequireNotDeleting(resourceId, CancellationToken.None);
            var operation = await store.FindAsync(id, CancellationToken.None)
                ?? throw Conflict("deployment_not_found", "Deployment operation not found.", 404);
            Scope(operation, designId, resourceId);
            policy.RequireApprovedProject(operation.ProjectId);
            var priorAttempt = await store.FindAttemptAsync(requestId, CancellationToken.None);
            if (priorAttempt is not null)
            {
                if (priorAttempt.DeploymentId != id)
                    throw Conflict("request_id_reused", "The retry ID already belongs to another operation.");
                return StorageDeploymentResponse.From(operation);
            }
            if (operation.Status == "pending" && operation.LeaseUntilUtc > DateTime.UtcNow)
                return StorageDeploymentResponse.From(operation);
            if (inspectOnly && operation.Status == "pending" && operation.CurrentAttemptId is null)
                return StorageDeploymentResponse.From(operation); // Definitely queued, not yet dispatched.
            if (!inspectOnly)
            {
                if (retry && operation.Status != "failed" && !(operation.Status == "pending" && operation.CurrentAttemptId is null))
                    return StorageDeploymentResponse.From(operation); // Unknown requires read-only reconciliation.
                if (!retry && (operation.Status != "pending" || operation.CurrentAttemptId is not null))
                    return StorageDeploymentResponse.From(operation);
            }
            if (!inspectOnly)
            {
                var current = await resources.GetAggregateAsync(resourceId, CancellationToken.None);
                if (current?.Revision != operation.ResourceRevision)
                {
                    operation.Status = "failed";
                    operation.Code = "revision_changed";
                    operation.UpdatedAtUtc = DateTime.UtcNow;
                    operation.Version++;
                    await transaction.CommitAsync(CancellationToken.None);
                    return StorageDeploymentResponse.From(operation);
                }
            }
            previousStatus = operation.Status;
            marker = operation.OwnershipMarker;
            target = new(resourceId, operation.ProjectId, operation.BucketName, operation.Location);
            store.AddAttempt(new StorageDeploymentAttempt { Id = requestId, DeploymentId = id });
            operation.CurrentAttemptId = requestId;
            operation.Status = "pending";
            operation.Code = inspectOnly ? "checking" : "deploying";
            operation.LeaseUntilUtc = DateTime.UtcNow.AddSeconds(45);
            operation.UpdatedAtUtc = DateTime.UtcNow;
            operation.Version++;
            await transaction.CommitAsync(CancellationToken.None);
        }

        CloudBucketResult result;
        // A disconnected frontend cannot cancel an already committed external operation.
        using (var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(20)))
        {
            try
            {
                result = inspectOnly ? await cloud.InspectAsync(target, marker, timeout.Token)
                    : await cloud.EnsureAsync(target, marker, timeout.Token);
            }
            catch (Exception) { result = new("unknown", "provider_unconfirmed"); }
        }
        if (result.Status is not ("succeeded" or "failed" or "unknown") ||
            result.Status == "succeeded" && result.Identity is null ||
            !System.Text.RegularExpressions.Regex.IsMatch(result.Code, "^[a-z_]{1,60}$"))
            result = new("unknown", "provider_protocol_error");
        if (inspectOnly && previousStatus == "failed" && result.Code == "bucket_not_found")
            result = new("failed", "not_created");

        await using (var transaction = await store.LockResourceAsync(resourceId, CancellationToken.None))
        {
            await RequireNotDeleting(resourceId, CancellationToken.None);
            var operation = await store.FindAsync(id, CancellationToken.None)
                ?? throw Conflict("deployment_not_found", "Deployment operation not found.", 404);
            // An expired, superseded execution must not overwrite a newer verification.
            if (operation.CurrentAttemptId != requestId) return StorageDeploymentResponse.From(operation);
            operation.Status = result.Status;
            operation.Code = result.Code;
            operation.OwnershipVerified = result.Status == "succeeded";
            operation.LeaseUntilUtc = null;
            operation.UpdatedAtUtc = DateTime.UtcNow;
            operation.Version++;
            if (result.Identity is { } remote)
            {
                operation.RemoteProjectNumber = remote.ProjectNumber;
                operation.RemoteBucketId = remote.BucketId;
                operation.RemoteMetageneration = remote.Metageneration;
            }
            await transaction.CommitAsync(CancellationToken.None);
            return StorageDeploymentResponse.From(operation);
        }
    }

    private async Task RequireNotDeleting(Guid resourceId, CancellationToken ct)
    {
        if (await deletions.FindDeletionAsync(resourceId, ct) is not null)
            throw Conflict("resource_deleting", "This Resource has entered its deletion lifecycle.");
    }

    private static string Hash(string value) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value))).ToLowerInvariant();
    private static void Scope(StorageDeployment operation, Guid design, Guid resource)
    {
        if (operation.DesignId != design || operation.ResourceId != resource)
            throw Conflict("deployment_not_found", "Deployment operation not found in this Resource.", 404);
    }
    private static void Nonempty(params Guid[] ids)
    {
        if (ids.Any(id => id == Guid.Empty)) throw new ResourceValidationException("Nonempty UUIDs are required.");
    }
    private static ResourceConflictException Conflict(string code, string message, int status = 409) => new(code, message, status);
}
