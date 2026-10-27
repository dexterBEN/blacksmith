using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Blacksmith.Application.Interfaces;
using Blacksmith.Domain.Entities;
using Blacksmith.Infrastructure.Persistence;
using Blacksmith.TestSupport;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Providers.GoogleCloud;
using Xunit;

namespace Blacksmith.IntegrationTests;

public sealed class StorageDeploymentTests : IDisposable
{
    private readonly SqliteConnection _connection = new("Data Source=:memory:");
    private readonly DeploymentApiFactory _factory;
    private readonly HttpClient _client;
    private static readonly Guid Design = Guid.Parse("90000000-0000-0000-0000-000000000001");
    public StorageDeploymentTests()
    {
        _connection.Open();
        _factory = new(o => o.UseSqlite(_connection));
        _client = _factory.CreateClient(new WebApplicationFactoryClientOptions { BaseAddress = new("https://localhost") });
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<BlacksmithDbContext>();
        db.Database.EnsureCreated(); db.Designs.Add(new() { Id = Design, Name = "Deployment tests" }); db.SaveChanges();
    }
    internal static object Body(string bucket = "blacksmith-fixture", int x = 0, string project = "example-project-123") => new {
        name = "Cloud Storage", type = "gcp.storage.bucket", resourceTypeId = "10000000-0000-0000-0000-000000000002", x, y = 0,
        configuration = new { schemaVersion = 1, configuration = new { projectId = project, bucketName = bucket, location = "europe-west9" } }
    };
    private string Route(Guid resource, Guid operation) => $"/designs/{Design}/resources/{resource}/deployments/{operation}";
    private Task<HttpResponseMessage> Write(Guid resource, Guid operation, object body, string? tag = null,
        bool token = true, bool consent = true)
    {
        var request = new HttpRequestMessage(HttpMethod.Put, Route(resource, operation)) { Content = JsonContent.Create(body) };
        request.Headers.TryAddWithoutValidation(tag is null ? "If-None-Match" : "If-Match", tag ?? "*");
        Authorize(request, token, consent); return _client.SendAsync(request);
    }
    private static void Authorize(HttpRequestMessage request, bool token = true, bool consent = true) {
        if (token) request.Headers.Add("X-Blacksmith-Deployment-Token", DeploymentApiFactory.TestToken);
        if (consent) request.Headers.Add("X-Blacksmith-Deploy-Consent", "true");
    }
    private async Task<JsonElement> Json(HttpResponseMessage response, HttpStatusCode expected = HttpStatusCode.OK) {
        Assert.Equal(expected, response.StatusCode); return await response.Content.ReadFromJsonAsync<JsonElement>();
    }
    [Fact] public async Task One_command_persists_canonical_config_and_outcome_replay_is_read_only() {
        var r = Guid.NewGuid(); var op = Guid.NewGuid();
        _factory.Cloud.BeforeCreate = async () => { using var scope = _factory.Services.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<BlacksmithDbContext>();
            Assert.Equal(1, await db.Resources.CountAsync()); Assert.Equal(1, await db.ResourceConfigurations.CountAsync());
            Assert.Equal("pending", (await db.StorageDeployments.SingleAsync()).Status);
        };
        var result = await Json(await Write(r, op, Body()));
        Assert.Equal("succeeded", result.GetProperty("deployment").GetProperty("status").GetString());
        Assert.Equal(1, result.GetProperty("resource").GetProperty("revision").GetInt64());
        Assert.DoesNotContain("OwnershipMarker", result.GetRawText(), StringComparison.OrdinalIgnoreCase);
        await Json(await Write(r, op, Body()));
        await Json(await _client.GetAsync(Route(r,op)));
        await _client.GetAsync($"/designs/{Design}/resources?include=configuration");
        Assert.Equal(1, _factory.Cloud.Creates); Assert.Equal(0, _factory.Cloud.Inspections);
        Assert.Equal(HttpStatusCode.Conflict, (await Write(r, op, Body("different-bucket"))).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await _client.DeleteAsync($"/resources/{r}")).StatusCode);
    }
    [Theory] [InlineData(false,true,401)] [InlineData(true,false,400)]
    public async Task Token_and_deliberate_consent_precede_save(bool token, bool consent, int status) {
        Assert.Equal(status, (int)(await Write(Guid.NewGuid(), Guid.NewGuid(), Body(), token:token,consent:consent)).StatusCode);
        Assert.Equal(0,_factory.Cloud.Creates);
        using var scope = _factory.Services.CreateScope(); Assert.Empty(scope.ServiceProvider.GetRequiredService<BlacksmithDbContext>().Resources);
    }
    [Fact] public async Task Policy_blocks_arbitrary_project_before_save() {
        Assert.Equal(HttpStatusCode.Forbidden, (await Write(Guid.NewGuid(),Guid.NewGuid(),Body(project:"other-project-123"))).StatusCode);
        Assert.Equal(0,_factory.Cloud.Creates);
    }
    [Theory] [InlineData("Production",true)] [InlineData("Development",false)]
    public async Task Deployment_is_disabled_by_default_and_outside_development(string environment,bool enabled) {
        using var factory = new DeploymentApiFactory(o=>o.UseSqlite(_connection),environment,enabled);
        using var client = factory.CreateClient(new WebApplicationFactoryClientOptions{BaseAddress=new("https://localhost")});
        using var request=new HttpRequestMessage(HttpMethod.Put,Route(Guid.NewGuid(),Guid.NewGuid())){Content=JsonContent.Create(Body())};
        Authorize(request);request.Headers.TryAddWithoutValidation("If-None-Match","*");
        Assert.Equal(HttpStatusCode.Forbidden,(await client.SendAsync(request)).StatusCode); Assert.Equal(0,factory.Cloud.Creates);
    }
    [Theory] [InlineData("blacksmith-reject","failed")] [InlineData("blacksmith-lost","unknown")]
    public async Task Failures_retain_saved_cube_data_and_unknown_reconciles_same_owned_bucket(string bucket,string status) {
        var r=Guid.NewGuid();var op=Guid.NewGuid();
        var result=await Json(await Write(r,op,Body(bucket)));
        Assert.Equal(status,result.GetProperty("deployment").GetProperty("status").GetString());
        await Json(await Write(r,op,Body(bucket))); Assert.Equal(1,_factory.Cloud.Creates);
        var resource=await Json(await _client.GetAsync($"/resources/{r}?include=configuration"));
        Assert.Equal(bucket,resource.GetProperty("configuration").GetProperty("configuration").GetProperty("bucketName").GetString());
        using var request=new HttpRequestMessage(HttpMethod.Post,Route(r,op)+"/reconcile");Authorize(request,consent:false);
        var checkedResult=await Json(await _client.SendAsync(request));
        Assert.Equal(status=="unknown"?"succeeded":"failed",checkedResult.GetProperty("status").GetString());
        Assert.Equal(1,_factory.Cloud.Creates);Assert.Equal(1,_factory.Cloud.Inspections);
    }
    [Fact] public async Task Failed_retry_deduplicates_request_id_and_rejects_stale_revision() {
        var r=Guid.NewGuid();var op=Guid.NewGuid();await Write(r,op,Body("blacksmith-reject"));
        var attempt=Guid.NewGuid();
        async Task<HttpResponseMessage> Retry(long rev) {
            var request=new HttpRequestMessage(HttpMethod.Post,Route(r,op)+$"/retry/{attempt}");Authorize(request);
            request.Headers.TryAddWithoutValidation("If-Match",$"\"resource-{r:N}-r{rev}\"");return await _client.SendAsync(request);
        }
        Assert.Equal(HttpStatusCode.PreconditionFailed,(await Retry(2)).StatusCode);
        await Json(await Retry(1));await Json(await Retry(1));Assert.Equal(2,_factory.Cloud.Creates);
    }
    [Fact] public async Task Same_name_unrelated_bucket_is_never_adopted() {
        var r=Guid.NewGuid();_factory.Cloud.AddUnrelated(new(r,"example-project-123","blacksmith-fixture","europe-west9"));
        var result=await Json(await Write(r,Guid.NewGuid(),Body()));
        Assert.Equal("unrelated_bucket",result.GetProperty("deployment").GetProperty("code").GetString());
        Assert.False(result.GetProperty("deployment").GetProperty("ownershipVerified").GetBoolean());
    }
    [Fact] public async Task Saved_configuration_only_and_second_resource_never_call_provider() {
        var r=Guid.NewGuid();var op=Guid.NewGuid();await Write(r,op,Body());
        using var request=new HttpRequestMessage(HttpMethod.Put,$"/designs/{Design}/resources/{Guid.NewGuid()}"){Content=JsonContent.Create(Body("second-bucket",1))};
        request.Headers.TryAddWithoutValidation("If-None-Match","*"); Assert.Equal(HttpStatusCode.Created,(await _client.SendAsync(request)).StatusCode);
        var records=await _client.GetFromJsonAsync<JsonElement>($"/designs/{Design}/resources?include=configuration");
        Assert.Equal(2,records.GetArrayLength()); Assert.False(records[1].TryGetProperty("deployment",out _));
        Assert.Equal(1,_factory.Cloud.Creates);
        Assert.Equal(HttpStatusCode.Conflict,(await Write(r,Guid.NewGuid(),Body("retargeted-bucket"),$"\"resource-{r:N}-r1\"")).StatusCode);
    }
    [Fact] public void Google_request_and_ownership_readback_apply_all_v1_settings() {
        var target=new CloudBucketTarget(Guid.NewGuid(),"example-project-123","blacksmith-fixture","europe-west9");
        var bucket=GoogleCloudStorageService.BuildBucket(target,"server-marker");
        Assert.Equal(target.Location,bucket.Location);Assert.Equal("STANDARD",bucket.StorageClass);
        Assert.True(bucket.IamConfiguration.UniformBucketLevelAccess.Enabled);Assert.Equal("enforced",bucket.IamConfiguration.PublicAccessPrevention);
        bucket.ProjectNumber=123456789;bucket.Id=target.BucketName;bucket.Metageneration=1;
        Assert.Equal("succeeded",GoogleCloudStorageService.Verify(bucket,target,"server-marker","123456789").Status);
        Assert.Equal("unrelated_bucket",GoogleCloudStorageService.Verify(bucket,target,"other-marker","123456789").Code);
        Assert.Equal("unrelated_bucket",GoogleCloudStorageService.Verify(bucket,target,"server-marker","987654321").Code);
        bucket.Location="US";Assert.Equal("remote_settings_mismatch",GoogleCloudStorageService.Verify(bucket,target,"server-marker","123456789").Code);
    }
    [Fact] public async Task Stale_existing_resource_revision_cannot_deploy_or_overwrite_configuration() {
        var id=Guid.NewGuid();
        async Task<HttpResponseMessage> Save(object body,string? tag=null) {
            var request=new HttpRequestMessage(HttpMethod.Put,$"/designs/{Design}/resources/{id}"){Content=JsonContent.Create(body)};
            request.Headers.TryAddWithoutValidation(tag is null?"If-None-Match":"If-Match",tag??"*");return await _client.SendAsync(request);
        }
        await Save(Body());await Save(Body("newer-bucket"),$"\"resource-{id:N}-r1\"");
        Assert.Equal(HttpStatusCode.PreconditionFailed,(await Write(id,Guid.NewGuid(),Body(),$"\"resource-{id:N}-r1\"")).StatusCode);
        Assert.Equal(0,_factory.Cloud.Creates);
        using var scope=_factory.Services.CreateScope();Assert.Empty(scope.ServiceProvider.GetRequiredService<BlacksmithDbContext>().StorageDeployments);
    }
    [Fact] public async Task Provider_exception_is_unknown_without_exposing_exception_or_credentials() {
        _factory.Cloud.BeforeCreate=()=>throw new InvalidOperationException("fixture-sensitive-value-must-not-be-echoed");
        var response=await Write(Guid.NewGuid(),Guid.NewGuid(),Body());var body=await response.Content.ReadAsStringAsync();
        Assert.Equal(HttpStatusCode.OK,response.StatusCode);Assert.DoesNotContain("fixture-sensitive-value",body);
        Assert.Contains("provider_unconfirmed",body);Assert.Contains("unknown",body);
    }
    public void Dispose(){_client.Dispose();_factory.Dispose();_connection.Dispose();}
}
