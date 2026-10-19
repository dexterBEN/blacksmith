using Blacksmith.Domain.Entities;

namespace Blacksmith.Application.Interfaces;

public interface IResourceRepository
{
    Task<IReadOnlyList<ResourceEntity>> ListByDesignIdAsync(Guid designId, CancellationToken ct);
    /// <summary>Returns resources in descending creation-time order.</summary>
    Task<IReadOnlyList<ResourceEntity>> ListAsync(CancellationToken ct);
    /// <summary>Returned resources participate in the current persistence unit of work.</summary>
    Task<ResourceEntity?> GetByIdAsync(Guid id, CancellationToken ct);
    void Add(ResourceEntity resource);
    void Remove(ResourceEntity resource);
    Task SaveChangesAsync(CancellationToken ct);
}
