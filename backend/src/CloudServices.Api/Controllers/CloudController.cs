using CloudServices.Core;
using Microsoft.AspNetCore.Mvc;

namespace CloudServices.Api.Controllers;

[ApiController]
[Route("cloud_services")]
public class CloudController : ControllerBase
{
    private readonly ICloudStorageService _cloudStorage;

    public CloudController(ICloudStorageService cloudStorage)
    {
        _cloudStorage = cloudStorage;
    }

    [HttpGet("ping")]
    public IActionResult Ping()
    {
        return Ok(new { message = "CloudServices backend is alive 🚀"});
    }

    [HttpPost("create-bucket")]
    public async Task<IActionResult> CreateBucket(
        [FromQuery] string projectId,
        [FromQuery] string bucketName
    )
    {
        if(string.IsNullOrWhiteSpace(projectId) || string.IsNullOrWhiteSpace(bucketName))
        {
            return BadRequest("projectId and bucketName are mandatory");
        }

        var createdName = await _cloudStorage.CreateBucketAsync(projectId, bucketName);

        return Ok(new { message = $"Bucket {createdName} create in project {projectId}"});
    }
}