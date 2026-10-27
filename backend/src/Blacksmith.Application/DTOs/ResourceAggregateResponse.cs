using System.Text.Json.Serialization;

namespace Blacksmith.Application.DTOs;

// Opt-in representation only; legacy metadata DTOs remain unchanged.
public sealed record ResourceAggregateResponse(Guid Id, Guid DesignId, Guid? ResourceTypeId,
    string Name, int X, int Y, string Type, DateTime CreatedAtUtc, long Revision,
    string ConfigurationState, ResourceConfigurationResponse? Configuration,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] StorageDeploymentResponse? Deployment = null);

public sealed record ConfiguredResourceResult(ResourceAggregateResponse Resource, string Outcome);
