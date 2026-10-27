using System.Text;
using System.Text.Json;
using Blacksmith.Application.DTOs;
using Blacksmith.Application.Exceptions;
using Blacksmith.Application.Validation;
using Blacksmith.Domain.Entities;

namespace Blacksmith.Application.Services;

public sealed partial class ResourceService
{
    public async Task<ResourceAggregateResponse?> GetAggregateAsync(Guid id, CancellationToken ct)
    {
        var resource = await repository.GetAggregateAsync(id, ct);
        return resource is null ? null : Aggregate(resource);
    }

    public async Task<IReadOnlyList<ResourceAggregateResponse>> ListAggregatesAsync(Guid designId, CancellationToken ct)
    {
        if (!await designs.ExistsAsync(designId, ct)) throw new DesignNotFoundException(designId);
        return (await repository.ListAggregatesAsync(designId, ct)).Select(Aggregate).ToArray();
    }

    public async Task<ConfiguredResourceResult> WriteConfiguredAsync(Guid designId, Guid id, JsonElement request,
        bool createOnly, long? expectedRevision, CancellationToken ct)
    {
        if (id == Guid.Empty || designId == Guid.Empty) throw new ResourceValidationException("Resource and Design UUIDs must be nonempty.");
        if (createOnly == expectedRevision.HasValue || expectedRevision is <= 0)
            throw new ResourceValidationException("Specify create-only or a positive expected revision.");
        var write = ConfiguredResourceWrite.Parse(request);
        if (!await designs.ExistsAsync(designId, ct)) throw new DesignNotFoundException(designId);
        var catalog = await resourceTypes.GetByIdAsync(write.ResourceTypeId, ct)
            ?? throw new ResourceTypeNotFoundException(write.ResourceTypeId);
        if (catalog.Code != CloudStorageConfigurationV1.CatalogCode)
            throw new ResourceValidationException("Cloud Storage configuration requires the storage catalog classification.");

        var resource = await repository.GetForUpdateAsync(id, ct);
        if (createOnly && resource is not null)
            throw new ResourceConflictException("resource_exists", "The Resource ID already exists. Read it before reconciling this intent.", 412);
        if (!createOnly && resource is null)
            throw new ResourceConflictException("resource_not_found", "Resource not found.", 404);
        if (resource is not null)
        {
            if (resource.DesignId != designId)
                throw new ResourceConflictException("resource_design_mismatch", "The Resource belongs to a different Design.");
            if (resource.Revision != expectedRevision)
                throw new ResourceConflictException("revision_conflict", "The Resource changed. Read it before retrying.", 412);
            if (resource.Type != write.Type || resource.ResourceTypeId is Guid existingCatalog &&
                (await resourceTypes.GetByIdAsync(existingCatalog, ct))?.Code != CloudStorageConfigurationV1.CatalogCode)
                throw new ResourceValidationException("The persisted Resource type/catalog cannot be converted by configured PUT.");
        }

        var stored = resource is null ? null : await repository.GetConfigurationAsync(id, ct);
        if (resource is not null && resource.Name == write.Name && resource.Type == write.Type &&
            resource.ResourceTypeId == write.ResourceTypeId && resource.X == write.X && resource.Y == write.Y &&
            Canonical(stored)?.GetRawText() == write.Configuration.GetRawText())
            return new(ValidatedAggregate(resource, write.Configuration), "unchanged");

        if (resource is null)
        {
            // PostgreSQL timestamps have microsecond precision; return the same value that read-back will expose.
            resource = new ResourceEntity { Id = id, DesignId = designId, Type = write.Type,
                CreatedAtUtc = new DateTime(DateTime.UtcNow.Ticks / 10 * 10, DateTimeKind.Utc) };
            repository.Add(resource);
        }
        else resource.Revision = ResourceRevision.Next(resource.Revision);
        resource.Name = write.Name;
        resource.Type = write.Type;
        resource.ResourceTypeId = write.ResourceTypeId;
        resource.X = write.X;
        resource.Y = write.Y;
        if (stored is null)
        {
            stored = new ResourceConfiguration { ResourceId = id };
            repository.AddConfiguration(stored);
        }
        stored.SchemaVersion = 1;
        stored.Configuration = write.Configuration.GetRawText();
        await repository.SaveChangesAsync(ct);
        return new(ValidatedAggregate(resource, write.Configuration), createOnly ? "created" : "updated");
    }

    private static JsonElement? Canonical(ResourceConfiguration? stored)
    {
        if (stored is null || stored.SchemaVersion != 1 ||
            Encoding.UTF8.GetByteCount(stored.Configuration) > CloudStorageConfigurationV1.MaxRequestBytes) return null;
        try
        {
            using var document = JsonDocument.Parse(stored.Configuration,
                new JsonDocumentOptions { MaxDepth = CloudStorageConfigurationV1.MaxDepth });
            return CloudStorageConfigurationV1.Normalize(document.RootElement);
        }
        catch (Exception error) when (error is JsonException or ResourceValidationException) { return null; }
    }

    private static ResourceAggregateResponse Aggregate(ResourceEntity resource)
    {
        var supportedType = resource.Type == CloudStorageConfigurationV1.ResourceType &&
            (resource.ResourceTypeId is null || resource.ResourceType?.Code == CloudStorageConfigurationV1.CatalogCode);
        var canonical = supportedType ? Canonical(resource.Configuration) : null;
        return canonical is JsonElement configuration ? ValidatedAggregate(resource, configuration)
            : new(resource.Id, resource.DesignId, resource.ResourceTypeId, resource.Name, resource.X, resource.Y,
                resource.Type, DateTime.SpecifyKind(resource.CreatedAtUtc, DateTimeKind.Utc), resource.Revision,
                resource.Configuration is null ? "absent" : "unsupported", null, LatestDeployment(resource));
    }

    private static ResourceAggregateResponse ValidatedAggregate(ResourceEntity resource, JsonElement configuration) =>
        new(resource.Id, resource.DesignId, resource.ResourceTypeId, resource.Name, resource.X, resource.Y,
            resource.Type, DateTime.SpecifyKind(resource.CreatedAtUtc, DateTimeKind.Utc), resource.Revision, "validated", new(resource.Id, 1, configuration), LatestDeployment(resource));

    private static StorageDeploymentResponse? LatestDeployment(ResourceEntity resource) =>
        resource.Deployments.OrderByDescending(x => x.CreatedAtUtc).ThenByDescending(x => x.Id).FirstOrDefault() is { } operation
            ? StorageDeploymentResponse.From(operation) : null;
}
