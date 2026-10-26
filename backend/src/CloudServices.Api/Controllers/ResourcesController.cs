using Blacksmith.Application.DTOs;
using Blacksmith.Application.Exceptions;
using Blacksmith.Application.Interfaces;
using Microsoft.AspNetCore.Mvc;
using System.Globalization;
using System.Text.Json;
using Blacksmith.Application.Validation;

namespace CloudServices.Api.Controllers;

[ApiController]
[Route("resources")]
[ResourceConflictFilter]
public sealed class ResourcesController(IResourceService resources) : ControllerBase
{
    [HttpPost]
    public async Task<IActionResult> Create([FromBody] CreateResourceRequest request, CancellationToken ct)
    {
        try
        {
            var resource = await resources.CreateAsync(request, ct);
            return CreatedAtAction(nameof(GetById), new { id = resource.Id }, resource);
        }
        catch (ResourceValidationException exception)
        {
            return BadRequest(new { error = exception.Message });
        }
        catch (DesignNotFoundException exception)
        {
            return NotFound(new { error = exception.Message });
        }
        catch (ResourceTypeNotFoundException exception)
        {
            return NotFound(new { error = exception.Message });
        }
    }

    [HttpGet]
    public async Task<IActionResult> List(CancellationToken ct) => Ok(await resources.ListAsync(ct));

    [HttpGet("{id:guid}")]
    public async Task<IActionResult> GetById([FromRoute] Guid id, CancellationToken ct, [FromQuery] string? include = null)
    {
        if (include is not null)
        {
            if (include != "configuration") return BadRequest(new { code = "invalid_include", error = "Supported include: configuration." });
            var aggregate = await resources.GetAggregateAsync(id, ct);
            if (aggregate is null) return NotFound(new { code = "resource_not_found", error = "Resource not found." });
            Response.Headers.ETag = Tag(id, aggregate.Revision);
            return Ok(aggregate);
        }
        var resource = await resources.GetByIdAsync(id, ct);
        return resource is null ? NotFound() : Ok(resource);
    }

    [HttpPut("/designs/{designId:guid}/resources/{id:guid}")]
    [RequestSizeLimit(CloudStorageConfigurationV1.MaxRequestBytes)]
    public async Task<IActionResult> WriteConfigured(Guid designId, Guid id, [FromBody] JsonElement request, CancellationToken ct)
    {
        try
        {
            if (Request.ContentLength > CloudStorageConfigurationV1.MaxRequestBytes) throw new ConfigurationPayloadTooLargeException();
            var createHeader = Request.Headers.IfNoneMatch;
            var editHeader = Request.Headers.IfMatch;
            var create = createHeader.Count == 1 && createHeader[0] == "*";
            long? revision = null;
            if (createHeader.Count == 0 && editHeader.Count == 0)
                return StatusCode(428, new { code = "precondition_required", error = "Use If-None-Match: * to create or a Resource If-Match tag to edit." });
            if (createHeader.Count != 0 && (!create || editHeader.Count != 0))
                throw new ResourceValidationException("Use exactly one supported write precondition.");
            if (!create)
            {
                var prefix = $"\"resource-{id:N}-r";
                var tag = editHeader.Count == 1 ? editHeader[0] : null;
                if (tag is null || !tag.StartsWith(prefix, StringComparison.Ordinal) || !tag.EndsWith('"') ||
                    !long.TryParse(tag.AsSpan(prefix.Length, tag.Length - prefix.Length - 1), NumberStyles.None,
                        CultureInfo.InvariantCulture, out var value) || value <= 0 || tag != Tag(id, value))
                    throw new ResourceValidationException("If-Match must be one strong revision tag for this Resource, obtained from aggregate GET.");
                revision = value;
            }
            var result = await resources.WriteConfiguredAsync(designId, id, request, create, revision, ct);
            Response.Headers["X-Resource-Write-Outcome"] = result.Outcome;
            // Validation can normalize the request: obtain a strong validator from GET, not this transformed PUT.
            if (result.Outcome == "created") return Created($"/resources/{id}?include=configuration", result.Resource);
            return Ok(result.Resource);
        }
        catch (ResourceValidationException error) { return BadRequest(new { code = "invalid_payload", error = error.Message }); }
        catch (ConfigurationPayloadTooLargeException error) { return StatusCode(413, new { code = "payload_too_large", error = error.Message }); }
        catch (DesignNotFoundException) { return NotFound(new { code = "design_not_found", error = "Design not found." }); }
        catch (ResourceTypeNotFoundException) { return NotFound(new { code = "catalog_not_found", error = "Resource catalog entry not found." }); }
    }

    private static string Tag(Guid id, long revision) => $"\"resource-{id:N}-r{revision.ToString(CultureInfo.InvariantCulture)}\"";

    [HttpPut("{id:guid}")]
    public async Task<IActionResult> Update([FromRoute] Guid id, [FromBody] UpdateResourceRequest request, CancellationToken ct)
    {
        try
        {
            var resource = await resources.UpdateAsync(id, request, ct);
            return resource is null ? NotFound() : Ok(resource);
        }
        catch (ResourceValidationException exception)
        {
            return BadRequest(new { error = exception.Message });
        }
        catch (DesignNotFoundException exception)
        {
            return NotFound(new { error = exception.Message });
        }
        catch (ResourceTypeNotFoundException exception)
        {
            return NotFound(new { error = exception.Message });
        }
    }

    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Delete([FromRoute] Guid id, CancellationToken ct) =>
        await resources.DeleteAsync(id, ct) ? NoContent() : NotFound();
}
