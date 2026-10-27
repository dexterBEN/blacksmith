using CloudServices.Core;
using Microsoft.AspNetCore.Mvc;

namespace CloudServices.Api.Controllers;

[ApiController]
[Route("cloud_services")]
public class CloudController : ControllerBase
{
    [HttpGet("ping")]
    public IActionResult Ping()
    {
        return Ok(new { message = "CloudServices backend is alive 🚀"});
    }

    [HttpPost("create-bucket")]
    public IActionResult CreateBucket(
        [FromQuery] string projectId,
        [FromQuery] string bucketName
    )
    {
        return StatusCode(410, new { code = "legacy_provisioning_disabled", error = "Use the authorized Resource-linked Save & Deploy workflow." });
    }
}
