using Blacksmith.Application.DTOs;
using Blacksmith.Application.Exceptions;
using Blacksmith.Application.Interfaces;
using Blacksmith.Domain.Entities;
using Blacksmith.Application.Validation;

namespace Blacksmith.Application.Services;

public sealed partial class ResourceService(
    IResourceRepository repository, IDesignRepository designs, IResourceTypeRepository resourceTypes) : IResourceService
{
    public async Task<ResourceResponse> CreateAsync(CreateResourceRequest request, CancellationToken ct)
    {
        Validate(request.Name, request.Type);
        var resourceTypeId = await ResolveResourceTypeAsync(request.Type.Trim(), request.ResourceTypeId, null, ct);
        var designId = request.DesignId ?? LegacyDesign.Id;
        if (request.DesignId is null) await designs.EnsureLegacyDesignAsync(ct);
        else if (!await designs.ExistsAsync(designId, ct)) throw new DesignNotFoundException(designId);
        var resource = new ResourceEntity
        {
            DesignId = designId,
            ResourceTypeId = resourceTypeId,
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
        var resource = await repository.GetForUpdateAsync(id, ct);
        if (resource is null) return null;

        var resourceTypeId = await ResolveResourceTypeAsync(request.Type.Trim(), request.ResourceTypeId, resource, ct);
        if (await repository.HasConfigurationAsync(id, ct))
        {
            if (request.Type.Trim() != resource.Type)
                throw new ResourceValidationException("A configured Resource cannot change type through metadata-only PUT.");
            if (resource.Type == CloudStorageConfigurationV1.ResourceType && resourceTypeId is Guid catalogId &&
                (await resourceTypes.GetByIdAsync(catalogId, ct))?.Code != CloudStorageConfigurationV1.CatalogCode)
                throw new ResourceValidationException("The configured Resource requires the storage catalog classification.");
        }
        if (request.DesignId is Guid designId)
        {
            if (!await designs.ExistsAsync(designId, ct)) throw new DesignNotFoundException(designId);
            resource.DesignId = designId;
        }
        resource.Name = request.Name.Trim();
        resource.ResourceTypeId = resourceTypeId;
        resource.Type = request.Type.Trim();
        resource.X = request.X;
        resource.Y = request.Y;
        resource.Revision = ResourceRevision.Next(resource.Revision);
        await repository.SaveChangesAsync(ct);
        return ToResponse(resource);
    }

    public async Task<bool> DeleteAsync(Guid id, CancellationToken ct)
    {
        var resource = await repository.GetForUpdateAsync(id, ct);
        if (resource is null) return false;

        repository.Remove(resource);
        await repository.SaveChangesAsync(ct);
        return true;
    }

    private async Task<Guid?> ResolveResourceTypeAsync(
        string legacyType, Guid? requestedId, ResourceEntity? existing, CancellationToken ct)
    {
        if (requestedId is Guid id)
        {
            var requested = await resourceTypes.GetByIdAsync(id, ct);
            if (requested is null) throw new ResourceTypeNotFoundException(id);
            var inferred = await resourceTypes.GetByCodeAsync(legacyType, ct);
            if (inferred is not null && inferred.Id != id)
                throw new ResourceValidationException("Type and resourceTypeId refer to different catalog entries");
            return id;
        }

        // Older clients must not erase an explicit classification when editing unrelated fields.
        if (existing?.ResourceTypeId is Guid previous && existing.Type == legacyType) return previous;
        return (await resourceTypes.GetByCodeAsync(legacyType, ct))?.Id;
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
