using Blacksmith.Domain.Entities;

namespace Blacksmith.Application.Interfaces;

public interface IResourceRepository
{
    Task<IReadOnlyList<ResourceEntity>> ListByDesignIdAsync(Guid designId, CancellationToken ct);
    /// <summary>Returns resources in descending creation-time order.</summary>
    Task<IReadOnlyList<ResourceEntity>> ListAsync(CancellationToken ct);
    /// <summary>Returned resources participate in the current persistence unit of work.</summary>
    Task<ResourceEntity?> GetByIdAsync(Guid id, CancellationToken ct);
    /// <summary>Keep the Resource stable until SaveChanges or repository disposal.</summary>
    Task<ResourceEntity?> GetForUpdateAsync(Guid id, CancellationToken ct);
    Task<ResourceConfiguration?> GetConfigurationAsync(Guid resourceId, CancellationToken ct);
    Task<bool> HasConfigurationAsync(Guid resourceId, CancellationToken ct);
    void AddConfiguration(ResourceConfiguration configuration);
    void Add(ResourceEntity resource);
    void Remove(ResourceEntity resource);
    Task SaveChangesAsync(CancellationToken ct);
}
