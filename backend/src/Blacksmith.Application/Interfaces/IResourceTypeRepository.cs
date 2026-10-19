using Blacksmith.Domain.Entities;

namespace Blacksmith.Application.Interfaces;

public interface IResourceTypeRepository
{
    Task<IReadOnlyList<ResourceTypeEntity>> ListAsync(CancellationToken ct);
    Task<ResourceTypeEntity?> GetByIdAsync(Guid id, CancellationToken ct);
    Task<ResourceTypeEntity?> GetByCodeAsync(string code, CancellationToken ct);
}
