namespace Blacksmith.Application.DTOs;

public sealed class CreateDesignRequest
{
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
}
