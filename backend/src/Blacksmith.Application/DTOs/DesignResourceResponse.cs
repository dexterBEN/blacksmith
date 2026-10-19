namespace Blacksmith.Application.DTOs;

public sealed record DesignResourceResponse(
    Guid Id, Guid DesignId, string Name, int X, int Y, string Type, DateTime CreatedAtUtc);
