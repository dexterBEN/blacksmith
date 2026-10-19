using Blacksmith.Application.Interfaces;
using Microsoft.AspNetCore.Mvc;

namespace CloudServices.Api.Controllers;

[ApiController]
[Route("resource-types")]
public sealed class ResourceTypesController(IResourceTypeService resourceTypes) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> List(CancellationToken ct) => Ok(await resourceTypes.ListAsync(ct));

    [HttpGet("{id:guid}")]
    public async Task<IActionResult> GetById(Guid id, CancellationToken ct)
    {
        var type = await resourceTypes.GetByIdAsync(id, ct);
        return type is null ? NotFound() : Ok(type);
    }
}
