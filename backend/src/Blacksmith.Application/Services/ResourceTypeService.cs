using Blacksmith.Application.DTOs;
using Blacksmith.Application.Interfaces;
using Blacksmith.Domain.Entities;

namespace Blacksmith.Application.Services;

public sealed class ResourceTypeService(IResourceTypeRepository repository) : IResourceTypeService
{
    public async Task<IReadOnlyList<ResourceTypeResponse>> ListAsync(CancellationToken ct) =>
        (await repository.ListAsync(ct)).Select(ToResponse).ToArray();

    public async Task<ResourceTypeResponse?> GetByIdAsync(Guid id, CancellationToken ct)
    {
        var type = await repository.GetByIdAsync(id, ct);
        return type is null ? null : ToResponse(type);
    }

    private static ResourceTypeResponse ToResponse(ResourceTypeEntity type) =>
        new(type.Id, type.Code, type.DisplayName, type.Category);
}
