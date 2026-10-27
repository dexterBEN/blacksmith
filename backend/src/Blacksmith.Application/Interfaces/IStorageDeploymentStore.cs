using Blacksmith.Domain.Entities;

namespace Blacksmith.Application.Interfaces;

public interface IDeploymentTransaction : IAsyncDisposable
{
    Task CommitAsync(CancellationToken ct);
}

public interface IStorageDeploymentStore
{
    Task<IDeploymentTransaction> LockResourceAsync(Guid resourceId, CancellationToken ct);
    Task<StorageDeployment?> FindAsync(Guid id, CancellationToken ct);
    Task<StorageDeployment?> FirstForResourceAsync(Guid id, CancellationToken ct);
    Task<StorageDeployment?> ForRevisionAsync(Guid id, long revision, CancellationToken ct);
    Task<StorageDeploymentAttempt?> FindAttemptAsync(Guid requestId, CancellationToken ct);
    void Add(StorageDeployment operation);
    void AddAttempt(StorageDeploymentAttempt attempt);
}

public interface IDeploymentTargetPolicy
{
    void RequireApprovedProject(string projectId);
}
