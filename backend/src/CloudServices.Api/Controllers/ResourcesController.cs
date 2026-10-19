using Blacksmith.Application.DTOs;
using Blacksmith.Application.Exceptions;
using Blacksmith.Application.Interfaces;
using Microsoft.AspNetCore.Mvc;

namespace CloudServices.Api.Controllers;

[ApiController]
[Route("resources")]
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
    }

    [HttpGet]
    public async Task<IActionResult> List(CancellationToken ct) => Ok(await resources.ListAsync(ct));

    [HttpGet("{id:guid}")]
    public async Task<IActionResult> GetById([FromRoute] Guid id, CancellationToken ct)
    {
        var resource = await resources.GetByIdAsync(id, ct);
        return resource is null ? NotFound() : Ok(resource);
    }

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
    }

    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Delete([FromRoute] Guid id, CancellationToken ct) =>
        await resources.DeleteAsync(id, ct) ? NoContent() : NotFound();
}
