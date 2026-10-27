using Blacksmith.Domain.Entities;

namespace Blacksmith.Application.DTOs;

public sealed record StorageDeploymentResponse(Guid Id, Guid ResourceId, Guid DesignId,
    long ResourceRevision, string ProjectId, string BucketName, string Location,
    string Status, string Code, DateTime UpdatedAtUtc, string? RemoteProjectNumber,
    string? RemoteBucketId, string? RemoteMetageneration, bool OwnershipVerified)
{
    public static StorageDeploymentResponse From(StorageDeployment operation) => new(
        operation.Id, operation.ResourceId, operation.DesignId, operation.ResourceRevision,
        operation.ProjectId, operation.BucketName, operation.Location,
        operation.Status == "pending" && operation.LeaseUntilUtc < DateTime.UtcNow ? "unknown" : operation.Status,
        operation.Status == "pending" && operation.LeaseUntilUtc < DateTime.UtcNow ? "execution_interrupted" : operation.Code,
        operation.UpdatedAtUtc, operation.RemoteProjectNumber, operation.RemoteBucketId,
        operation.RemoteMetageneration, operation.OwnershipVerified);
}

public sealed record StorageDeploymentResult(ResourceAggregateResponse Resource, StorageDeploymentResponse Deployment);
