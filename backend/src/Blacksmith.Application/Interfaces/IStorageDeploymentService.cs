using System.Text.Json;
using Blacksmith.Application.DTOs;

namespace Blacksmith.Application.Interfaces;

public interface IStorageDeploymentService
{
    Task<StorageDeploymentResult> SaveAndDeployAsync(Guid designId, Guid resourceId, Guid operationId,
        JsonElement body, bool createOnly, long? revision, CancellationToken ct);
    Task<StorageDeploymentResponse> ReadAsync(Guid designId, Guid resourceId, Guid operationId, CancellationToken ct);
    Task<StorageDeploymentResponse> ReconcileAsync(Guid designId, Guid resourceId, Guid operationId, CancellationToken ct);
    Task<StorageDeploymentResponse> RetryAsync(Guid designId, Guid resourceId, Guid operationId,
        Guid requestId, long revision, CancellationToken ct);
}
