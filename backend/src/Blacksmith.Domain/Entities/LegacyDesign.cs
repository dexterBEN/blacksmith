namespace Blacksmith.Domain.Entities;

// Stable owner for migrated resources and clients that do not yet send a designId.
public static class LegacyDesign
{
    public static readonly Guid Id = new("00000000-0000-0000-0000-000000000001");
    public const string Name = "Legacy design";
    public const string Description = "Resources migrated from the single-canvas application.";
}
