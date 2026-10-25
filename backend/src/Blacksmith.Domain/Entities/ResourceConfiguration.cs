namespace Blacksmith.Domain.Entities;

/// <summary>Optional, nonsecret configuration; its format version is independent of EF migrations.</summary>
public sealed class ResourceConfiguration
{
    public Guid ResourceId { get; set; }
    public ResourceEntity? Resource { get; set; }
    public int SchemaVersion { get; set; }

    // Raw JSON mapped to native jsonb, not a JSON-encoded string. Replace the
    // immutable document to update it; EF tracks the string without DOM lifetimes.
    public string Configuration { get; set; } = string.Empty;
}
