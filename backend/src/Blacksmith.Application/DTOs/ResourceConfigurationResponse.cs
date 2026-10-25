using System.Text.Json;

namespace Blacksmith.Application.DTOs;

public sealed record ResourceConfigurationResponse(Guid ResourceId, int SchemaVersion, JsonElement Configuration);
