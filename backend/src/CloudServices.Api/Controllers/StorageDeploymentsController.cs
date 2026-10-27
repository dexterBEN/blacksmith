using System.Text.Json;
using Blacksmith.Application.Exceptions;
using Blacksmith.Application.Interfaces;
using Blacksmith.Application.Validation;
using CloudServices.Api;
using Microsoft.AspNetCore.Mvc;

namespace CloudServices.Api.Controllers;

[ApiController]
[Route("designs/{designId:guid}/resources/{resourceId:guid}/deployments/{operationId:guid}")]
[ResourceConflictFilter]
public sealed class StorageDeploymentsController(IStorageDeploymentService deployments, DeploymentPolicy policy) : ControllerBase
{
    [HttpPut]
    [RequestSizeLimit(CloudStorageConfigurationV1.MaxRequestBytes)]
    public async Task<IActionResult> SaveAndDeploy(Guid designId, Guid resourceId, Guid operationId,
        [FromBody] JsonElement request, CancellationToken ct)
    {
        policy.RequireLocalToken(Request, consent: true);
        try
        {
            var create = Request.Headers.IfNoneMatch.Count == 1 && Request.Headers.IfNoneMatch[0] == "*";
            var edit = ParseRevision(resourceId);
            if (create && Request.Headers.IfMatch.Count != 0 || !create && Request.Headers.IfNoneMatch.Count != 0)
                throw new ResourceValidationException("Use exactly one supported Resource precondition.");
            if (!create && edit is null) return StatusCode(428, new { code = "precondition_required", error = "A Resource revision or create-only precondition is required." });
            var result = await deployments.SaveAndDeployAsync(designId, resourceId, operationId, request, create, edit, ct);
            return StatusCode(result.Deployment.Status == "pending" ? 202 : 200, result);
        }
        catch (ResourceValidationException) { return BadRequest(new { code = "invalid_payload", error = "Invalid configured Resource or Cloud Storage v1 data." }); }
        catch (ConfigurationPayloadTooLargeException) { return StatusCode(413, new { code = "payload_too_large", error = "Request exceeds 16 KiB." }); }
        catch (DesignNotFoundException) { return NotFound(new { code = "design_not_found", error = "Design not found." }); }
        catch (ResourceTypeNotFoundException) { return NotFound(new { code = "catalog_not_found", error = "Resource catalog entry not found." }); }
    }

    [HttpGet]
    public async Task<IActionResult> Read(Guid designId, Guid resourceId, Guid operationId, CancellationToken ct) =>
        Ok(await deployments.ReadAsync(designId, resourceId, operationId, ct));

    [HttpPost("reconcile")]
    public async Task<IActionResult> Reconcile(Guid designId, Guid resourceId, Guid operationId, CancellationToken ct)
    {
        policy.RequireLocalToken(Request);
        var result = await deployments.ReconcileAsync(designId, resourceId, operationId, ct);
        return StatusCode(result.Status == "pending" ? 202 : 200, result);
    }

    [HttpPost("retry/{requestId:guid}")]
    public async Task<IActionResult> Retry(Guid designId, Guid resourceId, Guid operationId, Guid requestId, CancellationToken ct)
    {
        policy.RequireLocalToken(Request, consent: true);
        var revision = ParseRevision(resourceId);
        if (revision is null) return StatusCode(428, new { code = "precondition_required", error = "Read the Resource revision before retrying." });
        var result = await deployments.RetryAsync(designId, resourceId, operationId, requestId, revision.Value, ct);
        return StatusCode(result.Status == "pending" ? 202 : 200, result);
    }

    private long? ParseRevision(Guid resourceId)
    {
        if (Request.Headers.IfMatch.Count == 0) return null;
        var tag = Request.Headers.IfMatch.Count == 1 ? Request.Headers.IfMatch[0] : null;
        var prefix = $"\"resource-{resourceId:N}-r";
        if (tag is null || !tag.StartsWith(prefix, StringComparison.Ordinal) || !tag.EndsWith('"') ||
            !long.TryParse(tag.AsSpan(prefix.Length, tag.Length - prefix.Length - 1),
                System.Globalization.NumberStyles.None, System.Globalization.CultureInfo.InvariantCulture, out var revision) ||
            revision <= 0 || tag != $"{prefix}{revision}\"")
            throw new ResourceConflictException("invalid_precondition", "Use one strong revision tag from Resource GET.", 400);
        return revision;
    }
}
