using Blacksmith.Application.DTOs;

namespace Blacksmith.Application.Interfaces;

public interface IStorageDeletionService
{
    Task<StorageDeletionResponse> DeleteAsync(Guid designId, Guid resourceId, Guid operationId, long revision, CancellationToken ct);
    Task<StorageDeletionResponse> ReadAsync(Guid designId, Guid resourceId, Guid operationId, CancellationToken ct);
    Task<StorageDeletionResponse> ReconcileAsync(Guid designId, Guid resourceId, Guid operationId, CancellationToken ct);
    Task<StorageDeletionResponse> RetryAsync(Guid designId, Guid resourceId, Guid operationId, Guid requestId, long revision, CancellationToken ct);
}
