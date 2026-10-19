using Blacksmith.Application.DTOs;

namespace Blacksmith.Application.Interfaces;

public interface IResourceTypeService
{
    Task<IReadOnlyList<ResourceTypeResponse>> ListAsync(CancellationToken ct);
    Task<ResourceTypeResponse?> GetByIdAsync(Guid id, CancellationToken ct);
}
