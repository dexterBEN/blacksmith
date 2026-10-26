using Blacksmith.Application.DTOs;
using Blacksmith.Application.Exceptions;
using Blacksmith.Application.Interfaces;
using Microsoft.AspNetCore.Mvc;

namespace CloudServices.Api.Controllers;

[ApiController]
[Route("designs")]
public sealed class DesignsController(IDesignService designs, IResourceService resources) : ControllerBase
{
    [HttpPost]
    public async Task<IActionResult> Create([FromBody] CreateDesignRequest request, CancellationToken ct)
    {
        try
        {
            var design = await designs.CreateAsync(request, ct);
            return CreatedAtAction(nameof(GetById), new { id = design.Id }, design);
        }
        catch (DesignValidationException exception) { return BadRequest(new { error = exception.Message }); }
    }

    [HttpGet]
    public async Task<IActionResult> List(CancellationToken ct) => Ok(await designs.ListAsync(ct));

    [HttpGet("{id:guid}")]
    public async Task<IActionResult> GetById(Guid id, CancellationToken ct)
    {
        var design = await designs.GetByIdAsync(id, ct);
        return design is null ? NotFound() : Ok(design);
    }

    [HttpPut("{id:guid}")]
    public async Task<IActionResult> Update(Guid id, [FromBody] UpdateDesignRequest request, CancellationToken ct)
    {
        try
        {
            var design = await designs.UpdateAsync(id, request, ct);
            return design is null ? NotFound() : Ok(design);
        }
        catch (DesignValidationException exception) { return BadRequest(new { error = exception.Message }); }
    }

    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Delete(Guid id, CancellationToken ct)
    {
        try { return await designs.DeleteAsync(id, ct) ? NoContent() : NotFound(); }
        catch (DesignDeletionConflictException exception) { return Conflict(new { error = exception.Message }); }
    }

    [HttpGet("{id:guid}/resources")]
    public async Task<IActionResult> ListResources(Guid id, CancellationToken ct, [FromQuery] string? include = null)
    {
        if (include is not null && include != "configuration") return BadRequest(new { code = "invalid_include", error = "Supported include: configuration." });
        try { return include is null ? Ok(await resources.ListByDesignIdAsync(id, ct)) : Ok(await resources.ListAggregatesAsync(id, ct)); }
        catch (DesignNotFoundException exception) { return NotFound(new { error = exception.Message }); }
    }
}
