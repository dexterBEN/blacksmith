using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Blacksmith.Application.Exceptions;

namespace Blacksmith.Application.Validation;

/// <summary>Local v1 validation only: no credentials, SDK or Google API access.</summary>
public static class CloudStorageConfigurationV1
{
    public const string ResourceType = "gcp.storage.bucket";
    public const string CatalogCode = "storage";
    public const int MaxRequestBytes = 16 * 1024;
    public const int MaxDepth = 8;
    private static readonly HashSet<string> Locations = new(StringComparer.Ordinal)
        { "europe-west9", "us-central1", "northamerica-northeast1" };
    private static readonly string[] Fields =
        ["projectId", "bucketName", "location", "storageClass", "uniformBucketLevelAccess", "publicAccessPrevention"];

    public static JsonElement ValidateRequest(JsonElement request)
    {
        if (request.ValueKind == JsonValueKind.Undefined)
            throw Invalid("A configuration request object is required.");
        if (Encoding.UTF8.GetByteCount(request.GetRawText()) > MaxRequestBytes)
            throw new ConfigurationPayloadTooLargeException();
        CheckDepth(request, 1);
        CheckKeys(request, ["schemaVersion", "configuration"]);
        if (!request.TryGetProperty("schemaVersion", out var version) || version.ValueKind != JsonValueKind.Number ||
            !version.TryGetInt32(out var number) || number != 1)
            throw Invalid("Only schemaVersion 1 is supported.");
        if (!request.TryGetProperty("configuration", out var configuration))
            throw Invalid("configuration must be an object.");
        return Normalize(configuration);
    }

    public static JsonElement Normalize(JsonElement configuration)
    {
        CheckKeys(configuration, Fields);
        var project = RequiredString(configuration, "projectId");
        if (!Matches(project, "^[a-z][a-z0-9-]{4,28}[a-z0-9]$") ||
            project.Contains("google", StringComparison.Ordinal) || project.Contains("ssl", StringComparison.Ordinal))
            throw Invalid("projectId must be a supported 6-30 character lowercase Google project ID.");
        var name = RequiredString(configuration, "bucketName");
        if (!Matches(name, "^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$") ||
            name.StartsWith("goog", StringComparison.Ordinal) || Matches(name, "g[o0]{2}gle"))
            throw Invalid("bucketName must use the supported 3-63 character lowercase letter/digit/hyphen format without reserved Google names.");
        var location = RequiredString(configuration, "location");
        if (!Locations.Contains(location))
            throw Invalid("location must be europe-west9, us-central1 or northamerica-northeast1.");
        if (configuration.TryGetProperty("storageClass", out var storage) &&
            (storage.ValueKind != JsonValueKind.String || storage.GetString() != "STANDARD"))
            throw Invalid("storageClass must be STANDARD.");
        if (configuration.TryGetProperty("uniformBucketLevelAccess", out var uniform) && uniform.ValueKind != JsonValueKind.True)
            throw Invalid("uniformBucketLevelAccess must be true.");
        if (configuration.TryGetProperty("publicAccessPrevention", out var publicAccess) &&
            (publicAccess.ValueKind != JsonValueKind.String || publicAccess.GetString() != "enforced"))
            throw Invalid("publicAccessPrevention must be enforced.");
        // Fixed values are materialized even when omitted; no soft-delete policy is imposed.
        return JsonSerializer.SerializeToElement(new
        {
            projectId = project, bucketName = name, location,
            storageClass = "STANDARD", uniformBucketLevelAccess = true, publicAccessPrevention = "enforced"
        });
    }

    private static void CheckKeys(JsonElement value, string[] allowed)
    {
        if (value.ValueKind != JsonValueKind.Object) throw Invalid("Configuration and request roots must be JSON objects.");
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var property in value.EnumerateObject())
            if (!seen.Add(property.Name) || !allowed.Contains(property.Name, StringComparer.Ordinal))
                throw Invalid("Unsupported or duplicate fields are not allowed.");
    }

    private static string RequiredString(JsonElement value, string name)
    {
        if (!value.TryGetProperty(name, out var field) || field.ValueKind != JsonValueKind.String || string.IsNullOrWhiteSpace(field.GetString()))
            throw Invalid($"{name} is required and must be a non-empty string.");
        return field.GetString()!;
    }

    private static void CheckDepth(JsonElement value, int depth)
    {
        if (depth > MaxDepth) throw Invalid("Configuration request exceeds the maximum JSON depth of 8.");
        if (value.ValueKind == JsonValueKind.Object)
            foreach (var property in value.EnumerateObject()) CheckDepth(property.Value, depth + 1);
        else if (value.ValueKind == JsonValueKind.Array)
            foreach (var item in value.EnumerateArray()) CheckDepth(item, depth + 1);
    }

    private static bool Matches(string value, string pattern) => Regex.IsMatch(value, pattern, RegexOptions.CultureInvariant | RegexOptions.NonBacktracking);
    private static ResourceValidationException Invalid(string message) => new(message);
}
