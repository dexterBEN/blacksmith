namespace Blacksmith.Application.DTOs;

public sealed class UpdateResourceRequest
{
    public Guid? DesignId { get; set; }
    public string Name { get; set; } = string.Empty;
    public int X { get; set; }
    public int Y { get; set; }
    public string Type { get; set; } = string.Empty;
}
