using Blacksmith.Domain.Entities;

namespace Blacksmith.Application.Interfaces;

public interface IDesignRepository
{
    Task<IReadOnlyList<DesignEntity>> ListAsync(CancellationToken ct);
    Task<DesignEntity?> GetByIdAsync(Guid id, CancellationToken ct);
    Task<bool> ExistsAsync(Guid id, CancellationToken ct);
    /// Atomically deletes a Design and its resources, refusing any deployment history.
    Task<bool> DeleteUndeployedAsync(Guid id, CancellationToken ct);
    Task EnsureLegacyDesignAsync(CancellationToken ct);
    void Add(DesignEntity design);
    Task SaveChangesAsync(CancellationToken ct);
}
