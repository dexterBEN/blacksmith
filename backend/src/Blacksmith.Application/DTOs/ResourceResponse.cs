namespace Blacksmith.Application.DTOs;

public sealed record ResourceResponse(
    Guid Id, string Name, int X, int Y, string Type, DateTime CreatedAtUtc);
