namespace Blacksmith.Application.DTOs;

public sealed record DesignResponse(
    Guid Id, string Name, string? Description, DateTime CreatedAtUtc, DateTime UpdatedAtUtc);
