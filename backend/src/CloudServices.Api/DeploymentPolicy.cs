using System.Security.Cryptography;
using System.Text;
using Blacksmith.Application.Exceptions;
using Blacksmith.Application.Interfaces;

namespace CloudServices.Api;

/// Explicit single-operator local authorization; never accepts credentials in JSON.
public sealed class DeploymentPolicy(IConfiguration configuration, IHostEnvironment environment) : IDeploymentTargetPolicy
{
    public void RequireLocalToken(HttpRequest request, bool consent = false)
    {
        if (!environment.IsDevelopment() || !configuration.GetValue<bool>("BlacksmithDeployment:Enabled"))
            throw new ResourceConflictException("deployment_disabled", "Cloud deployment is disabled in this environment.", 403);
        var expected = configuration["BlacksmithDeployment:Token"] ?? "";
        var supplied = request.Headers["X-Blacksmith-Deployment-Token"].ToString();
        if (Encoding.UTF8.GetByteCount(expected) < 32 ||
            !CryptographicOperations.FixedTimeEquals(Encoding.UTF8.GetBytes(expected), Encoding.UTF8.GetBytes(supplied)))
            throw new ResourceConflictException("deployment_unauthorized", "Deployment authorization is required.", 401);
        if (consent && request.Headers["X-Blacksmith-Deploy-Consent"] != "true")
            throw new ResourceConflictException("consent_required", "Explicit approval of the target and possible cloud charges is required.", 400);
    }
    public void RequireApprovedProject(string projectId)
    {
        if (!environment.IsDevelopment() || !configuration.GetValue<bool>("BlacksmithDeployment:Enabled") ||
            !(configuration.GetSection("BlacksmithDeployment:ApprovedProjects").Get<string[]>() ?? [])
                .Contains(projectId, StringComparer.Ordinal))
            throw new ResourceConflictException("project_not_approved", "The deployment target is not enabled in the local project policy.", 403);
    }
}
