using Blacksmith.Application.DTOs;

namespace Blacksmith.Application.Interfaces;

public interface IResourceService
{
    Task<ResourceAggregateResponse?> GetAggregateAsync(Guid id, CancellationToken ct);
    Task<IReadOnlyList<ResourceAggregateResponse>> ListAggregatesAsync(Guid designId, CancellationToken ct);
    Task<ConfiguredResourceResult> WriteConfiguredAsync(Guid designId, Guid id, System.Text.Json.JsonElement request,
        bool createOnly, long? expectedRevision, CancellationToken ct);
    Task<IReadOnlyList<DesignResourceResponse>> ListByDesignIdAsync(Guid designId, CancellationToken ct);
    Task<ResourceResponse> CreateAsync(CreateResourceRequest request, CancellationToken ct);
    Task<IReadOnlyList<ResourceResponse>> ListAsync(CancellationToken ct);
    Task<ResourceResponse?> GetByIdAsync(Guid id, CancellationToken ct);
    Task<ResourceResponse?> UpdateAsync(Guid id, UpdateResourceRequest request, CancellationToken ct);
    Task<bool> DeleteAsync(Guid id, CancellationToken ct);
}
