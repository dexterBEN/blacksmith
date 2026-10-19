using Blacksmith.Application.DTOs;

namespace Blacksmith.Application.Interfaces;

public interface IResourceService
{
    Task<ResourceResponse> CreateAsync(CreateResourceRequest request, CancellationToken ct);
    Task<IReadOnlyList<ResourceResponse>> ListAsync(CancellationToken ct);
    Task<ResourceResponse?> GetByIdAsync(Guid id, CancellationToken ct);
    Task<ResourceResponse?> UpdateAsync(Guid id, UpdateResourceRequest request, CancellationToken ct);
    Task<bool> DeleteAsync(Guid id, CancellationToken ct);
}
