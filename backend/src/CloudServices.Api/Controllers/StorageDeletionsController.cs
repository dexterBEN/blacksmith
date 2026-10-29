using Blacksmith.Application.DTOs;
using Blacksmith.Application.Exceptions;
using Blacksmith.Application.Interfaces;
using Microsoft.AspNetCore.Mvc;

namespace CloudServices.Api.Controllers;

[ApiController]
[Route("designs/{designId:guid}/resources/{resourceId:guid}/deletions/{operationId:guid}")]
[ResourceConflictFilter]
public sealed class StorageDeletionsController(IStorageDeletionService deletions, DeploymentPolicy policy) : ControllerBase
{
    [HttpPut]
    public async Task<IActionResult> DeleteBucket(Guid designId, Guid resourceId, Guid operationId, CancellationToken ct)
    {
        Authorize(consent: true);
        var revision = Revision(resourceId);
        if (revision is null) return Precondition();
        return Outcome(await deletions.DeleteAsync(designId, resourceId, operationId, revision.Value, ct));
    }
    [HttpGet]
    public async Task<IActionResult> Read(Guid designId, Guid resourceId, Guid operationId, CancellationToken ct) =>
        Ok(await deletions.ReadAsync(designId, resourceId, operationId, ct));

    [HttpPost("reconcile")]
    public async Task<IActionResult> Reconcile(Guid designId, Guid resourceId, Guid operationId, CancellationToken ct)
    {
        Authorize(consent: false);
        return Outcome(await deletions.ReconcileAsync(designId, resourceId, operationId, ct));
    }
    [HttpPost("retry/{requestId:guid}")]
    public async Task<IActionResult> Retry(Guid designId, Guid resourceId, Guid operationId, Guid requestId, CancellationToken ct)
    {
        Authorize(consent: true);
        var revision = Revision(resourceId);
        if (revision is null) return Precondition();
        return Outcome(await deletions.RetryAsync(designId, resourceId, operationId, requestId, revision.Value, ct));
    }
    private void Authorize(bool consent)
    {
        policy.RequireLocalDeployment(Request);
        if (consent && Request.Headers["X-Blacksmith-Delete-Consent"] != "true")
            throw new ResourceConflictException("consent_required", "Explicit consent to delete the resource and its empty GCP bucket is required.", 400);
    }
    private long? Revision(Guid resourceId)
    {
        if (Request.Headers.IfNoneMatch.Count != 0)
            throw new ResourceConflictException("invalid_precondition", "Deletion requires If-Match, not If-None-Match.", 400);
        if (Request.Headers.IfMatch.Count == 0) return null;
        var tag = Request.Headers.IfMatch.Count == 1 ? Request.Headers.IfMatch[0] : null;
        var prefix = $"\"resource-{resourceId:N}-r";
        if (tag is null || !tag.StartsWith(prefix, StringComparison.Ordinal) || !tag.EndsWith('"') ||
            !long.TryParse(tag.AsSpan(prefix.Length, tag.Length - prefix.Length - 1),
                System.Globalization.NumberStyles.None, System.Globalization.CultureInfo.InvariantCulture, out var revision) ||
            revision <= 0 || tag != $"{prefix}{revision}\"")
            throw new ResourceConflictException("invalid_precondition", "Use one strong Resource revision tag.", 400);
        return revision;
    }
    private IActionResult Precondition() => StatusCode(428, new { code = "precondition_required", error = "Read the Resource revision before deletion." });
    private IActionResult Outcome(StorageDeletionResponse result) => StatusCode(result.Status == "pending" ? 202 : 200, result);
}
