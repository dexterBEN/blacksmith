namespace CloudServices.Api.Domain;

public sealed class ResourceEntity
{
    public Guid Id { get; set; }
    public string Name { get; set; } = string.Empty;

    public int X { get; set; }
    public int Y { get; set; }

    public string Type { get; set; } = string.Empty;

    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;
}