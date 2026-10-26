using System.Text.Json;
using Blacksmith.Application.Exceptions;
using Blacksmith.Application.Validation;
using Xunit;

namespace Blacksmith.Application.Tests;

public sealed class ResourceConfigurationValidationTests
{
    private const string Minimal = """{"schemaVersion":1,"configuration":{"projectId":"example-project-123","bucketName":"blacksmith-example-assets","location":"europe-west9"}}""";

    [Theory]
    [InlineData("europe-west9")]
    [InlineData("us-central1")]
    [InlineData("northamerica-northeast1")]
    public void Canonical_document_materializes_only_approved_fixed_values(string location)
    {
        using var input = JsonDocument.Parse(Minimal.Replace("europe-west9", location));
        var canonical = CloudStorageConfigurationV1.ValidateRequest(input.RootElement);
        Assert.Equal(new[] { "bucketName", "location", "projectId", "publicAccessPrevention", "storageClass", "uniformBucketLevelAccess" },
            canonical.EnumerateObject().Select(x => x.Name).Order());
        Assert.Equal("example-project-123", canonical.GetProperty("projectId").GetString());
        Assert.Equal(location, canonical.GetProperty("location").GetString());
        Assert.Equal("STANDARD", canonical.GetProperty("storageClass").GetString());
        Assert.True(canonical.GetProperty("uniformBucketLevelAccess").GetBoolean());
        Assert.Equal("enforced", canonical.GetProperty("publicAccessPrevention").GetString());
    }

    [Fact]
    public void Result_owns_its_json_and_accepts_explicit_fixed_values()
    {
        JsonElement canonical;
        using (var input = JsonDocument.Parse(Minimal.Replace("\"location\"", "\"storageClass\":\"STANDARD\",\"uniformBucketLevelAccess\":true,\"publicAccessPrevention\":\"enforced\",\"location\"")))
            canonical = CloudStorageConfigurationV1.ValidateRequest(input.RootElement);
        Assert.Equal("blacksmith-example-assets", canonical.GetProperty("bucketName").GetString());
    }

    [Theory]
    [InlineData("{}")]
    [InlineData("null")]
    [InlineData("[]")]
    [InlineData("1")]
    [InlineData("{\"schemaVersion\":1}")]
    [InlineData("{\"schemaVersion\":2,\"configuration\":{}}")]
    [InlineData("{\"schemaVersion\":\"1\",\"configuration\":{}}")]
    [InlineData("{\"schemaVersion\":1.0,\"configuration\":{}}")]
    [InlineData("{\"schemaVersion\":1,\"configuration\":[]}")]
    [InlineData("{\"schemaVersion\":1,\"configuration\":null}")]
    [InlineData("{\"schemaVersion\":1,\"configuration\":\"not an object\"}")]
    public void Invalid_roots_envelopes_and_versions_are_rejected(string json)
    {
        using var input = JsonDocument.Parse(json);
        Assert.Throws<ResourceValidationException>(() => CloudStorageConfigurationV1.ValidateRequest(input.RootElement));
    }

    [Theory]
    [InlineData("projectId", "abc")]
    [InlineData("projectId", "Example-project-123")]
    [InlineData("projectId", "1example-project")]
    [InlineData("projectId", "example-project-")]
    [InlineData("projectId", "example-google-project")]
    [InlineData("projectId", "example-ssl-project")]
    [InlineData("projectId", " example-project-123")]
    [InlineData("bucketName", "ab")]
    [InlineData("bucketName", "Uppercase-bucket")]
    [InlineData("bucketName", "bucket_name")]
    [InlineData("bucketName", "bucket.name")]
    [InlineData("bucketName", "192.168.1.1")]
    [InlineData("bucketName", "-bucket-name")]
    [InlineData("bucketName", "bucket-name-")]
    [InlineData("bucketName", "goog-bucket")]
    [InlineData("bucketName", "my-g00gle-bucket")]
    [InlineData("location", "US")]
    [InlineData("location", "EUROPE-WEST9")]
    [InlineData("location", "unknown-region")]
    public void Formats_and_explicit_regional_subset_are_conservative(string field, string value)
    {
        var values = Values(); values[field] = value;
        Reject(values);
    }

    [Theory]
    [InlineData("projectId")]
    [InlineData("bucketName")]
    [InlineData("location")]
    public void Required_fields_reject_missing_null_empty_and_wrong_type(string field)
    {
        foreach (var value in new object?[] { null, "", "   ", 42, true, new { nested = "value" } })
        {
            var values = Values(); values[field] = value; Reject(values);
        }
        var missing = Values(); missing.Remove(field); Reject(missing);
    }

    [Theory]
    [InlineData("storageClass", "NEARLINE")]
    [InlineData("storageClass", "standard")]
    [InlineData("uniformBucketLevelAccess", false)]
    [InlineData("uniformBucketLevelAccess", "true")]
    [InlineData("publicAccessPrevention", "inherited")]
    [InlineData("publicAccessPrevention", false)]
    [InlineData("private_key", "DO_NOT_ECHO_FIXTURE")]
    [InlineData("access_token", "DO_NOT_ECHO_FIXTURE")]
    [InlineData("credentials", "DO_NOT_ECHO_FIXTURE")]
    [InlineData("schemaVersion", 1)]
    [InlineData("softDeleteRetentionDays", 7)]
    [InlineData("unknown", "value")]
    public void Unsupported_policies_and_secret_bearing_keys_are_rejected(string field, object value)
    {
        var values = Values(); values[field] = value; Reject(values);
    }

    [Fact]
    public void Duplicate_and_case_variant_keys_in_both_objects_are_rejected()
    {
        foreach (var json in new[]
        {
            Minimal.Replace("\"schemaVersion\":1", "\"schemaVersion\":1,\"schemaVersion\":1"),
            Minimal.Replace("\"schemaVersion\":1", "\"schemaVersion\":1,\"SchemaVersion\":1"),
            Minimal.Replace("\"location\":\"europe-west9\"", "\"location\":\"europe-west9\",\"location\":\"us-central1\""),
            Minimal.Replace("\"location\":\"europe-west9\"", "\"location\":\"europe-west9\",\"Location\":\"europe-west9\""),
            Minimal.Replace("\"location\":\"europe-west9\"", "\"location\":\"europe-west9\",\"locati\\u006fn\":\"us-central1\""),
            Minimal.Replace("\"configuration\":", "\"type\":\"gcp.storage.bucket\",\"configuration\":")
        })
        {
            using var input = JsonDocument.Parse(json);
            Assert.Throws<ResourceValidationException>(() => CloudStorageConfigurationV1.ValidateRequest(input.RootElement));
        }
    }

    [Fact]
    public void Size_depth_and_length_limits_do_not_echo_values()
    {
        using var oversized = JsonDocument.Parse(Minimal.Replace("blacksmith-example-assets", new string('x', 17000)));
        Assert.Throws<ConfigurationPayloadTooLargeException>(() => CloudStorageConfigurationV1.ValidateRequest(oversized.RootElement));
        using var deep = JsonDocument.Parse(Minimal.Replace("\"europe-west9\"", new string('[', 12) + "0" + new string(']', 12)));
        Assert.Throws<ResourceValidationException>(() => CloudStorageConfigurationV1.ValidateRequest(deep.RootElement));
        foreach (var field in new[] { "projectId", "bucketName", "location" })
        { var values = Values(); values[field] = new string('a', 100); Reject(values); }
    }

    private static Dictionary<string, object?> Values() => new()
    { ["projectId"] = "example-project-123", ["bucketName"] = "blacksmith-example-assets", ["location"] = "europe-west9" };

    private static void Reject(Dictionary<string, object?> values)
    {
        var input = JsonSerializer.SerializeToElement(new { schemaVersion = 1, configuration = values });
        var error = Assert.Throws<ResourceValidationException>(() => CloudStorageConfigurationV1.ValidateRequest(input));
        Assert.DoesNotContain("DO_NOT_ECHO_FIXTURE", error.Message);
    }
}
