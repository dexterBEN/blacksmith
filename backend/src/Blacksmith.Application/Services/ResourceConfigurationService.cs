using System.Text;
using System.Text.Json;
using Blacksmith.Application.DTOs;
using Blacksmith.Application.Exceptions;
using Blacksmith.Application.Interfaces;
using Blacksmith.Application.Validation;
using Blacksmith.Domain.Entities;

namespace Blacksmith.Application.Services;

public sealed class ResourceConfigurationService(IResourceRepository resources, IResourceTypeRepository types)
    : IResourceConfigurationService
{
    public async Task<ResourceConfigurationResponse?> GetAsync(Guid resourceId, CancellationToken ct)
    {
        var resource = await resources.GetByIdAsync(resourceId, ct);
        if (resource is null) return null;
        var stored = await resources.GetConfigurationAsync(resourceId, ct);
        if (stored is null) return null;
        await CheckResource(resource, ct);
        try
        {
            if (stored.SchemaVersion != 1 || Encoding.UTF8.GetByteCount(stored.Configuration) > CloudStorageConfigurationV1.MaxRequestBytes)
                throw new StoredConfigurationUnsupportedException();
            using var parsed = JsonDocument.Parse(stored.Configuration, new JsonDocumentOptions { MaxDepth = CloudStorageConfigurationV1.MaxDepth });
            return new(resourceId, 1, CloudStorageConfigurationV1.Normalize(parsed.RootElement));
        }
        catch (Exception error) when (error is JsonException or ResourceValidationException)
        {
            // Never expose an unvalidated historical payload or its parsing error.
            throw new StoredConfigurationUnsupportedException();
        }
    }

    public async Task<ResourceConfigurationResponse?> ReplaceAsync(Guid resourceId, JsonElement request, CancellationToken ct)
    {
        var canonical = CloudStorageConfigurationV1.ValidateRequest(request);
        var resource = await resources.GetForUpdateAsync(resourceId, ct);
        if (resource is null) return null;
        await CheckResource(resource, ct);
        var stored = await resources.GetConfigurationAsync(resourceId, ct);
        if (stored is null)
        {
            stored = new ResourceConfiguration { ResourceId = resourceId };
            resources.AddConfiguration(stored);
        }
        stored.SchemaVersion = 1;
        stored.Configuration = canonical.GetRawText();
        resource.Revision = ResourceRevision.Next(resource.Revision);
        await resources.SaveChangesAsync(ct);
        return new(resourceId, 1, canonical);
    }

    private async Task CheckResource(ResourceEntity resource, CancellationToken ct)
    {
        if (resource.Type != CloudStorageConfigurationV1.ResourceType)
            throw new ResourceValidationException("Only resources of type gcp.storage.bucket support configuration v1.");
        if (resource.ResourceTypeId is Guid id &&
            (await types.GetByIdAsync(id, ct))?.Code != CloudStorageConfigurationV1.CatalogCode)
            throw new ResourceValidationException("The Resource type and catalog classification are incompatible.");
    }
}
