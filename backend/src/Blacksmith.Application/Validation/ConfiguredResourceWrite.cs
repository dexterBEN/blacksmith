using System.Text;
using System.Text.Json;
using Blacksmith.Application.Exceptions;

namespace Blacksmith.Application.Validation;

public sealed record ConfiguredResourceWrite(string Name, string Type, Guid ResourceTypeId, int X, int Y, JsonElement Configuration)
{
    public static ConfiguredResourceWrite Parse(JsonElement body)
    {
        if (body.ValueKind != JsonValueKind.Object) throw Invalid();
        if (Encoding.UTF8.GetByteCount(body.GetRawText()) > CloudStorageConfigurationV1.MaxRequestBytes)
            throw new ConfigurationPayloadTooLargeException();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        string[] allowed = ["name", "type", "resourceTypeId", "x", "y", "configuration"];
        foreach (var field in body.EnumerateObject())
            if (!seen.Add(field.Name) || !allowed.Contains(field.Name, StringComparer.Ordinal)) throw Invalid();
        if (!body.TryGetProperty("name", out var name) || name.ValueKind != JsonValueKind.String ||
            string.IsNullOrWhiteSpace(name.GetString()) || name.GetString()!.Trim().Length > 200 ||
            !body.TryGetProperty("type", out var type) || type.ValueKind != JsonValueKind.String ||
            type.GetString() != CloudStorageConfigurationV1.ResourceType ||
            !body.TryGetProperty("resourceTypeId", out var catalog) || catalog.ValueKind != JsonValueKind.String ||
            !catalog.TryGetGuid(out var catalogId) || catalogId == Guid.Empty ||
            !body.TryGetProperty("x", out var x) || x.ValueKind != JsonValueKind.Number || !x.TryGetInt32(out var column) ||
            !body.TryGetProperty("y", out var y) || y.ValueKind != JsonValueKind.Number || !y.TryGetInt32(out var row) ||
            !body.TryGetProperty("configuration", out var configuration)) throw Invalid();
        return new(name.GetString()!.Trim(), type.GetString()!, catalogId, column, row,
            CloudStorageConfigurationV1.ValidateRequest(configuration));
    }

    private static ResourceValidationException Invalid() => new(
        "A configured Resource requires name (1-200 characters), type gcp.storage.bucket, a catalog UUID, signed 32-bit integer x/y, and a complete configuration envelope. Unknown or duplicate fields are forbidden.");
}
