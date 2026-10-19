using Blacksmith.Application.DTOs;
using Blacksmith.Application.Exceptions;
using Blacksmith.Application.Interfaces;
using Blacksmith.Domain.Entities;

namespace Blacksmith.Application.Services;

public sealed class ResourceService(IResourceRepository repository, IDesignRepository designs) : IResourceService
{
    public async Task<ResourceResponse> CreateAsync(CreateResourceRequest request, CancellationToken ct)
    {
        Validate(request.Name, request.Type);
        var designId = request.DesignId ?? LegacyDesign.Id;
        if (request.DesignId is null) await designs.EnsureLegacyDesignAsync(ct);
        else if (!await designs.ExistsAsync(designId, ct)) throw new DesignNotFoundException(designId);
        var resource = new ResourceEntity
        {
            DesignId = designId,
            Id = Guid.NewGuid(), Name = request.Name.Trim(), Type = request.Type.Trim(),
            X = request.X, Y = request.Y, CreatedAtUtc = DateTime.UtcNow
        };
        repository.Add(resource);
        await repository.SaveChangesAsync(ct);
        return ToResponse(resource);
    }

    public async Task<IReadOnlyList<ResourceResponse>> ListAsync(CancellationToken ct)
    {
        var resources = await repository.ListAsync(ct);
        return resources.Select(ToResponse).ToArray();
    }

    public async Task<ResourceResponse?> GetByIdAsync(Guid id, CancellationToken ct)
    {
        var resource = await repository.GetByIdAsync(id, ct);
        return resource is null ? null : ToResponse(resource);
    }

    public async Task<IReadOnlyList<DesignResourceResponse>> ListByDesignIdAsync(Guid designId, CancellationToken ct)
    {
        if (!await designs.ExistsAsync(designId, ct)) throw new DesignNotFoundException(designId);
        return (await repository.ListByDesignIdAsync(designId, ct))
            .Select(resource => new DesignResourceResponse(resource.Id, resource.DesignId, resource.Name,
                resource.X, resource.Y, resource.Type, resource.CreatedAtUtc)).ToArray();
    }

    public async Task<ResourceResponse?> UpdateAsync(Guid id, UpdateResourceRequest request, CancellationToken ct)
    {
        // Keep validation before the lookup, including when the id does not exist.
        Validate(request.Name, request.Type);
        var resource = await repository.GetByIdAsync(id, ct);
        if (resource is null) return null;

        if (request.DesignId is Guid designId)
        {
            if (!await designs.ExistsAsync(designId, ct)) throw new DesignNotFoundException(designId);
            resource.DesignId = designId;
        }
        resource.Name = request.Name.Trim();
        resource.Type = request.Type.Trim();
        resource.X = request.X;
        resource.Y = request.Y;
        await repository.SaveChangesAsync(ct);
        return ToResponse(resource);
    }

    public async Task<bool> DeleteAsync(Guid id, CancellationToken ct)
    {
        var resource = await repository.GetByIdAsync(id, ct);
        if (resource is null) return false;

        repository.Remove(resource);
        await repository.SaveChangesAsync(ct);
        return true;
    }

    private static void Validate(string name, string type)
    {
        if (string.IsNullOrWhiteSpace(name))
            throw new ResourceValidationException("Name is required");
        if (string.IsNullOrWhiteSpace(type))
            throw new ResourceValidationException("Type is required");
    }

    private static ResourceResponse ToResponse(ResourceEntity resource) => new(
        resource.Id, resource.Name, resource.X, resource.Y, resource.Type, resource.CreatedAtUtc);
}
