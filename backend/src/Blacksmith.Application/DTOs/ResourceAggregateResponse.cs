namespace Blacksmith.Application.DTOs;

// Opt-in representation only; legacy metadata DTOs remain unchanged.
public sealed record ResourceAggregateResponse(Guid Id, Guid DesignId, Guid? ResourceTypeId,
    string Name, int X, int Y, string Type, DateTime CreatedAtUtc, long Revision,
    string ConfigurationState, ResourceConfigurationResponse? Configuration);

public sealed record ConfiguredResourceResult(ResourceAggregateResponse Resource, string Outcome);
