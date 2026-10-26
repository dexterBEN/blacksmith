using System.Text.Json;
using Blacksmith.Application.DTOs;

namespace Blacksmith.Application.Interfaces;

public interface IResourceConfigurationService
{
    Task<ResourceConfigurationResponse?> GetAsync(Guid resourceId, CancellationToken ct);
    Task<ResourceConfigurationResponse?> ReplaceAsync(Guid resourceId, JsonElement request, CancellationToken ct);
}
