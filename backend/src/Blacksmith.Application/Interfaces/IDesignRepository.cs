using Blacksmith.Domain.Entities;

namespace Blacksmith.Application.Interfaces;

public interface IDesignRepository
{
    Task<IReadOnlyList<DesignEntity>> ListAsync(CancellationToken ct);
    Task<DesignEntity?> GetByIdAsync(Guid id, CancellationToken ct);
    Task<bool> ExistsAsync(Guid id, CancellationToken ct);
    Task<bool> HasResourcesAsync(Guid id, CancellationToken ct);
    Task EnsureLegacyDesignAsync(CancellationToken ct);
    void Add(DesignEntity design);
    void Remove(DesignEntity design);
    Task SaveChangesAsync(CancellationToken ct);
}
