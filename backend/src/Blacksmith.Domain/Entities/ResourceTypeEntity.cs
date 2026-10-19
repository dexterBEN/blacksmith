namespace Blacksmith.Domain.Entities;

public sealed class ResourceTypeEntity
{
    public Guid Id { get; set; }
    public string Code { get; set; } = string.Empty;
    public string DisplayName { get; set; } = string.Empty;
    public string Category { get; set; } = string.Empty;
    public ICollection<ResourceEntity> Resources { get; set; } = new List<ResourceEntity>();
}
