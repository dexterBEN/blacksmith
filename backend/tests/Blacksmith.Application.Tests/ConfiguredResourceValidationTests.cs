using System.Text.Json;
using Blacksmith.Application.Exceptions;
using Blacksmith.Application.Validation;
using Xunit;

namespace Blacksmith.Application.Tests;

public sealed class ConfiguredResourceValidationTests
{
    private const string Valid = """{"name":" Display name ","type":"gcp.storage.bucket","resourceTypeId":"10000000-0000-0000-0000-000000000002","x":-100,"y":2147483647,"configuration":{"schemaVersion":1,"configuration":{"projectId":"example-project-123","bucketName":"blacksmith-example-assets","location":"europe-west9"}}}""";

    [Fact]
    public void Display_name_is_separate_from_bucket_and_signed_coordinates_are_not_viewport_bounded()
    {
        var input = JsonSerializer.Deserialize<JsonElement>(Valid);
        var write = ConfiguredResourceWrite.Parse(input);
        Assert.Equal("Display name", write.Name);
        Assert.Equal(-100, write.X);
        Assert.Equal(int.MaxValue, write.Y);
        Assert.Equal("blacksmith-example-assets", write.Configuration.GetProperty("bucketName").GetString());
        Assert.Equal(6, write.Configuration.EnumerateObject().Count());
    }

    [Theory]
    [InlineData("name", "null")]
    [InlineData("name", "\" \"")]
    [InlineData("type", "\"storage\"")]
    [InlineData("type", "\"gcp.compute.instance\"")]
    [InlineData("resourceTypeId", "\"00000000-0000-0000-0000-000000000000\"")]
    [InlineData("resourceTypeId", "\"invalid\"")]
    [InlineData("x", "2147483648")]
    [InlineData("y", "-2147483649")]
    [InlineData("x", "3.5")]
    [InlineData("y", "\"2\"")]
    [InlineData("configuration", "null")]
    [InlineData("configuration", "{}")]
    public void Invalid_fields_and_overflow_are_rejected(string field, string value)
    {
        var fields = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(Valid)!;
        fields[field] = JsonSerializer.Deserialize<JsonElement>(value);
        Assert.Throws<ResourceValidationException>(() => ConfiguredResourceWrite.Parse(JsonSerializer.SerializeToElement(fields)));
    }

    [Fact]
    public void Missing_long_unknown_duplicate_secret_fields_and_envelope_overrides_are_rejected()
    {
        foreach (var field in new[] { "name", "type", "resourceTypeId", "x", "y", "configuration" })
        {
            var fields = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(Valid)!;
            fields.Remove(field);
            Assert.Throws<ResourceValidationException>(() => ConfiguredResourceWrite.Parse(JsonSerializer.SerializeToElement(fields)));
        }
        foreach (var extra in new[] { "\"name\":\"DO_NOT_ECHO_FIXTURE\",", "\"Name\":\"DO_NOT_ECHO_FIXTURE\",", "\"designId\":\"DO_NOT_ECHO_FIXTURE\",", "\"private_key\":\"DO_NOT_ECHO_FIXTURE\"," })
        {
            var input = JsonSerializer.Deserialize<JsonElement>("{" + extra + Valid[1..]);
            var error = Assert.Throws<ResourceValidationException>(() => ConfiguredResourceWrite.Parse(input));
            Assert.DoesNotContain("DO_NOT_ECHO_FIXTURE", error.Message);
        }
        var longName = Valid.Replace(" Display name ", new string('a', 201));
        Assert.Throws<ResourceValidationException>(() => ConfiguredResourceWrite.Parse(JsonSerializer.Deserialize<JsonElement>(longName)));
        var huge = Valid.Replace(" Display name ", new string('a', 17000));
        Assert.Throws<ConfigurationPayloadTooLargeException>(() => ConfiguredResourceWrite.Parse(JsonSerializer.Deserialize<JsonElement>(huge)));
    }
}
