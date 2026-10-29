using Blacksmith.Application.Exceptions;
using Blacksmith.Application.Interfaces;

namespace CloudServices.Api;

/// Local development policy with explicit consent and approved target projects.
public sealed class DeploymentPolicy(IConfiguration configuration, IHostEnvironment environment) : IDeploymentTargetPolicy
{
    public void RequireLocalDeployment(HttpRequest request, bool consent = false)
    {
        if (!environment.IsDevelopment() || !configuration.GetValue<bool>("BlacksmithDeployment:Enabled"))
            throw new ResourceConflictException("deployment_disabled", "Cloud deployment is disabled in this environment.", 403);
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
