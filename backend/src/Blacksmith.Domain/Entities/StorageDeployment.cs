namespace Blacksmith.Domain.Entities;

/// One immutable Cloud Storage intent, with a durable current outcome.
public sealed class StorageDeployment
{
    public Guid Id { get; set; }
    public Guid ResourceId { get; set; }
    public ResourceEntity Resource { get; set; } = null!;
    public Guid DesignId { get; set; }
    public long ResourceRevision { get; set; }
    public string RequestHash { get; set; } = "";
    public string ConfigurationHash { get; set; } = "";
    public string Configuration { get; set; } = "";
    // Server-generated proof, never returned in API DTOs or logs.
    public string OwnershipMarker { get; set; } = "";
    public string ProjectId { get; set; } = "";
    public string BucketName { get; set; } = "";
    public string Location { get; set; } = "";
    public string Status { get; set; } = "pending";
    public string Code { get; set; } = "queued";
    public Guid? CurrentAttemptId { get; set; }
    public DateTime? LeaseUntilUtc { get; set; }
    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAtUtc { get; set; } = DateTime.UtcNow;
    public long Version { get; set; } = 1;
    public string? RemoteProjectNumber { get; set; }
    public string? RemoteBucketId { get; set; }
    public string? RemoteMetageneration { get; set; }
    public bool OwnershipVerified { get; set; }
    public ICollection<StorageDeploymentAttempt> Attempts { get; set; } = [];
}

/// Only request deduplication for this bounded operation, not a job/audit system.
public sealed class StorageDeploymentAttempt
{
    public Guid Id { get; set; }
    public Guid DeploymentId { get; set; }
    public StorageDeployment Deployment { get; set; } = null!;
    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;
}
