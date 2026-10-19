namespace Blacksmith.Application.DTOs;

public sealed class CreateResourceRequest
{
    public Guid? DesignId { get; set; }
    public Guid? ResourceTypeId { get; set; }
    public string Name { get; set; } = string.Empty;
    public int X { get; set; }
    public int Y { get; set; }
    public string Type { get; set; } = string.Empty;
}
