using System.Text.Json;
using Blacksmith.Application.DTOs;
using Blacksmith.Application.Exceptions;
using Blacksmith.Application.Interfaces;
using Blacksmith.Application.Validation;
using Microsoft.AspNetCore.Mvc;

namespace CloudServices.Api.Controllers;

[ApiController]
[Route("resources/{resourceId:guid}/configuration")]
[ResourceConflictFilter]
public sealed class ResourceConfigurationsController(IResourceConfigurationService configurations) : ControllerBase
{
    [HttpGet]
    [ProducesResponseType(typeof(ResourceConfigurationResponse), StatusCodes.Status200OK)]
    public async Task<IActionResult> Get(Guid resourceId, CancellationToken ct)
    {
        try
        {
            var result = await configurations.GetAsync(resourceId, ct);
            return result is null ? NotFound(new { error = "Resource configuration not found." }) : Ok(result);
        }
        catch (ResourceValidationException error) { return BadRequest(new { error = error.Message }); }
        catch (StoredConfigurationUnsupportedException error) { return Conflict(new { error = error.Message }); }
    }

    [HttpPut]
    [ProducesResponseType(typeof(ResourceConfigurationResponse), StatusCodes.Status200OK)]
    [RequestSizeLimit(CloudStorageConfigurationV1.MaxRequestBytes)]
    public async Task<IActionResult> Replace(Guid resourceId, [FromBody] JsonElement request, CancellationToken ct)
    {
        if (Request.ContentLength > CloudStorageConfigurationV1.MaxRequestBytes)
            return StatusCode(StatusCodes.Status413PayloadTooLarge, new { error = "Configuration request exceeds the 16384-byte limit." });
        try
        {
            var result = await configurations.ReplaceAsync(resourceId, request, ct);
            return result is null ? NotFound(new { error = "Resource not found." }) : Ok(result);
        }
        catch (ResourceValidationException error) { return BadRequest(new { error = error.Message }); }
        catch (ConfigurationPayloadTooLargeException error)
        { return StatusCode(StatusCodes.Status413PayloadTooLarge, new { error = error.Message }); }
    }
}
