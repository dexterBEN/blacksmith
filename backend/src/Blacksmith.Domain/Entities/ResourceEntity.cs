namespace Blacksmith.Domain.Entities;

public sealed class ResourceEntity
{
    public Guid Id { get; set; }
    public long Revision { get; set; } = 1;
    public Guid DesignId { get; set; }
    public DesignEntity? Design { get; set; }
    public Guid? ResourceTypeId { get; set; }
    public ResourceTypeEntity? ResourceType { get; set; }
    public ResourceConfiguration? Configuration { get; set; }
    public string Name { get; set; } = string.Empty;
    public int X { get; set; }
    public int Y { get; set; }
    public string Type { get; set; } = string.Empty;
    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;
}
