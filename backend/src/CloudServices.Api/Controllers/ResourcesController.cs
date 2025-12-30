using CloudServices.Api.Data;
using CloudServices.Api.Domain;
using CloudServices.Api.Dtos;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace CloudServices.Api.Controllers;

[ApiController]
[Route("resources")]
public sealed class ResourcesController : ControllerBase
{
    private readonly BlacksmithDbContext _db;

    public ResourcesController(BlacksmithDbContext db)
    {
        _db = db;
    }

    // POST /resources
    [HttpPost]
    public async Task<IActionResult> Create([FromBody] CreateResourceRequest request, CancellationToken ct)
    {
        // guardrails
        if (string.IsNullOrWhiteSpace(request.Name))
            return BadRequest(new { error = "Name is required" });

        if (string.IsNullOrWhiteSpace(request.Type))
            return BadRequest(new { error = "Type is required" });

        var entity = new ResourceEntity
        {
            Id = Guid.NewGuid(),
            Name = request.Name.Trim(),
            X = request.X,
            Y = request.Y,
            Type = request.Type.Trim(),
            CreatedAtUtc = DateTime.UtcNow
        };

        _db.Resources.Add(entity);
        await _db.SaveChangesAsync(ct);

        // 201 + location header
        return CreatedAtAction(nameof(GetById), new { id = entity.Id }, entity);
    }

    // GET /resources
    [HttpGet]
    public async Task<IActionResult> List(CancellationToken ct)
    {
        var items = await _db.Resources
            .AsNoTracking()
            .OrderByDescending(r => r.CreatedAtUtc)
            .ToListAsync(ct);

        return Ok(items);
    }

    // GET /resources/{id}
    [HttpGet("{id:guid}")]
    public async Task<IActionResult> GetById([FromRoute] Guid id, CancellationToken ct)
    {
        var item = await _db.Resources
            .AsNoTracking()
            .FirstOrDefaultAsync(r => r.Id == id, ct);

        if (item is null)
            return NotFound();

        return Ok(item);
    }

    // PUT /resources/{id}
    [HttpPut("{id:guid}")]
    public async Task<IActionResult> Update([FromRoute] Guid id, [FromBody] UpdateResourceRequest request, CancellationToken ct)
    {
        // guardrails
        if (string.IsNullOrWhiteSpace(request.Name))
            return BadRequest(new { error = "Name is required" });

        if (string.IsNullOrWhiteSpace(request.Type))
            return BadRequest(new { error = "Type is required" });

        var entity = await _db.Resources.FirstOrDefaultAsync(r => r.Id == id, ct);
        if (entity is null)
            return NotFound();

        entity.Name = request.Name.Trim();
        entity.X = request.X;
        entity.Y = request.Y;
        entity.Type = request.Type.Trim();

        await _db.SaveChangesAsync(ct);

        return Ok(entity);
    }

    // DELETE /resources/{id}
    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Delete([FromRoute] Guid id, CancellationToken ct)
    {
        var entity = await _db.Resources.FirstOrDefaultAsync(r => r.Id == id, ct);
        if (entity is null)
            return NotFound();

        _db.Resources.Remove(entity);
        await _db.SaveChangesAsync(ct);

        return NoContent();
    }
}