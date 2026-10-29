namespace Blacksmith.Domain.Entities;

// Durable recovery receipt, not a user audit log. No Resource FK: survives local cleanup.
public sealed class StorageDeletion
{
    public Guid ResourceId { get; set; }
    public Guid Id { get; set; }
    public Guid DesignId { get; set; }
    public long ResourceRevision { get; set; }
    public string ProjectId { get; set; } = "";
    public string BucketName { get; set; } = "";
    public string Location { get; set; } = "";
    public string OwnershipMarker { get; set; } = "";
    public string Status { get; set; } = "pending";
    public string Code { get; set; } = "deleting";
    public Guid CurrentAttemptId { get; set; }
    public DateTime? LeaseUntilUtc { get; set; }
    public DateTime UpdatedAtUtc { get; set; } = DateTime.UtcNow;
    public long Version { get; set; } = 1;
}

public sealed class StorageDeletionAttempt
{
    public Guid Id { get; set; }
    public Guid ResourceId { get; set; }
    public StorageDeletion Deletion { get; set; } = null!;
}
