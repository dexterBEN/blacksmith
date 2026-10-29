using Blacksmith.Domain.Entities;

namespace Blacksmith.Application.DTOs;

public sealed record StorageDeletionResponse(Guid Id, Guid ResourceId, Guid DesignId,
    long ResourceRevision, string ProjectId, string BucketName, string Location,
    string Status, string Code, DateTime UpdatedAtUtc)
{
    public static StorageDeletionResponse From(StorageDeletion deletion) => new(
        deletion.Id, deletion.ResourceId, deletion.DesignId, deletion.ResourceRevision,
        deletion.ProjectId, deletion.BucketName, deletion.Location,
        deletion.Status == "pending" && deletion.LeaseUntilUtc <= DateTime.UtcNow ? "unknown" : deletion.Status,
        deletion.Status == "pending" && deletion.LeaseUntilUtc <= DateTime.UtcNow ? "execution_interrupted" : deletion.Code,
        deletion.UpdatedAtUtc);
}
