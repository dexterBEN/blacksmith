namespace Blacksmith.Application.DTOs;

public sealed class UpdateDesignRequest
{
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
}
