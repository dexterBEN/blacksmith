namespace Blacksmith.Domain.Entities;

public sealed class DesignEntity
{
    public Guid Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAtUtc { get; set; } = DateTime.UtcNow;
    public ICollection<ResourceEntity> Resources { get; set; } = new List<ResourceEntity>();
}
