using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Blacksmith.Domain.Entities;
using Blacksmith.TestSupport;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace Blacksmith.PostgreSql.Tests;

public sealed class StorageDeploymentTests : PostgreSqlTestDatabase
{
    private async Task Seed() {
        await using var db=CreateContext();await db.Database.MigrateAsync();
        Assert.True(await db.Designs.AnyAsync(d=>d.Id==LegacyDesign.Id));
    }
    private static object Body(string bucket="blacksmith-postgres-lost") => new {
        name="Cloud Storage",type="gcp.storage.bucket",resourceTypeId="10000000-0000-0000-0000-000000000002",x=2,y=3,
        configuration=new {schemaVersion=1,configuration=new {projectId="example-project-123",bucketName=bucket,location="europe-west9"}}
    };
    private static string Route(Guid id,Guid op)=>$"/designs/{LegacyDesign.Id}/resources/{id}/deployments/{op}";
    private static HttpClient Client(DeploymentApiFactory factory)=>factory.CreateClient(new WebApplicationFactoryClientOptions {BaseAddress=new("https://localhost")});
    private static Task<HttpResponseMessage> Write(HttpClient client,Guid id,Guid op,object? body=null) {
        var request=new HttpRequestMessage(HttpMethod.Put,Route(id,op)){Content=JsonContent.Create(body??Body())};
        request.Headers.TryAddWithoutValidation("If-None-Match","*");request.Headers.Add("X-Blacksmith-Deployment-Token",DeploymentApiFactory.TestToken);
        request.Headers.Add("X-Blacksmith-Deploy-Consent","true");return client.SendAsync(request);
    }
    [PostgreSqlFact] public async Task Migration_atomic_save_before_external_call_and_unknown_survive_fresh_api() {
        await Seed();var id=Guid.NewGuid();var op=Guid.NewGuid();
        using(var factory=new DeploymentApiFactory(o=>o.UseNpgsql(ConnectionString))) {
            using var client=Client(factory);
            factory.Cloud.BeforeCreate=async()=> {
                Assert.Equal(1L,await Scalar<long>("SELECT count(*) FROM resources"));
                Assert.Equal(1L,await Scalar<long>("SELECT count(*) FROM resource_configurations"));
                Assert.Equal(1L,await Scalar<long>("SELECT count(*) FROM storage_deployments WHERE status='pending'"));
            };
            Assert.Equal(HttpStatusCode.OK,(await Write(client,id,op)).StatusCode);
            Assert.Equal(1,factory.Cloud.Creates);
        }
        using(var factory=new DeploymentApiFactory(o=>o.UseNpgsql(ConnectionString))) {
            using var client=Client(factory);
            var result=await client.GetFromJsonAsync<JsonElement>(Route(id,op));
            Assert.Equal("unknown",result.GetProperty("status").GetString());
            var record=await client.GetFromJsonAsync<JsonElement>($"/resources/{id}?include=configuration");
            Assert.Equal(op,record.GetProperty("deployment").GetProperty("id").GetGuid());
            Assert.Equal(1L,record.GetProperty("revision").GetInt64());
            Assert.Equal(HttpStatusCode.OK,(await Write(client,id,op)).StatusCode);
            Assert.Equal(0,factory.Cloud.Creates);Assert.Equal(0,factory.Cloud.Inspections);
        }
        Assert.Equal(1L,await Scalar<long>("SELECT count(*) FROM storage_deployments"));
        Assert.Equal(1L,await Scalar<long>("SELECT count(*) FROM storage_deployment_attempts"));
    }
    [PostgreSqlFact] public async Task Operation_insert_failure_rolls_back_resource_and_configuration_and_never_calls_cloud() {
        await Seed();await using(var db=CreateContext())await db.Database.ExecuteSqlRawAsync("ALTER TABLE storage_deployments ADD CONSTRAINT fixture_reject_intent CHECK (resource_revision <> 1)");
        using var factory=new DeploymentApiFactory(o=>o.UseNpgsql(ConnectionString));using var client=Client(factory);
        // Development exception middleware returns 500; all earlier writes must roll back.
        Assert.Equal(HttpStatusCode.InternalServerError,(await Write(client,Guid.NewGuid(),Guid.NewGuid())).StatusCode);
        Assert.Equal(0L,await Scalar<long>("SELECT count(*) FROM resources"));
        Assert.Equal(0L,await Scalar<long>("SELECT count(*) FROM resource_configurations"));
        Assert.Equal(0L,await Scalar<long>("SELECT count(*) FROM storage_deployments"));Assert.Equal(0,factory.Cloud.Creates);
    }
    [PostgreSqlFact] public async Task Concurrent_duplicate_request_has_one_claim_and_one_provider_call() {
        await Seed();using var factory=new DeploymentApiFactory(o=>o.UseNpgsql(ConnectionString));using var client=Client(factory);
        factory.Cloud.Entered=new(TaskCreationOptions.RunContinuationsAsynchronously);factory.Cloud.Continue=new(TaskCreationOptions.RunContinuationsAsynchronously);
        var id=Guid.NewGuid();var op=Guid.NewGuid();var first=Write(client,id,op,Body("blacksmith-postgres"));
        try {
            await factory.Cloud.Entered.Task.WaitAsync(TimeSpan.FromSeconds(15));
            Assert.Equal(HttpStatusCode.Accepted,(await Write(client,id,op,Body("blacksmith-postgres"))).StatusCode);
            Assert.Equal(1,factory.Cloud.Creates);
        } finally {factory.Cloud.Continue.TrySetResult();}
        Assert.Equal(HttpStatusCode.OK,(await first).StatusCode);
        Assert.Equal(1L,await Scalar<long>("SELECT count(*) FROM resources"));
        Assert.Equal(1L,await Scalar<long>("SELECT count(*) FROM storage_deployments"));
        Assert.Equal(1L,await Scalar<long>("SELECT count(*) FROM storage_deployment_attempts"));
    }
    [PostgreSqlFact] public async Task Interrupted_claim_becomes_unknown_and_cannot_automatically_recreate() {
        await Seed();using var factory=new DeploymentApiFactory(o=>o.UseNpgsql(ConnectionString));using var client=Client(factory);
        var id=Guid.NewGuid();var op=Guid.NewGuid();await Write(client,id,op,Body("blacksmith-postgres"));
        await using(var db=CreateContext()) {
            var row=await db.StorageDeployments.SingleAsync();row.Status="pending";row.LeaseUntilUtc=DateTime.UtcNow.AddMinutes(-1);await db.SaveChangesAsync();
        }
        var result=await client.GetFromJsonAsync<JsonElement>(Route(id,op));Assert.Equal("unknown",result.GetProperty("status").GetString());
        await Write(client,id,op,Body("blacksmith-postgres"));Assert.Equal(1,factory.Cloud.Creates);
        var request=new HttpRequestMessage(HttpMethod.Post,Route(id,op)+"/reconcile");request.Headers.Add("X-Blacksmith-Deployment-Token",DeploymentApiFactory.TestToken);
        var checkedResponse=await client.SendAsync(request);Assert.Equal(HttpStatusCode.OK,checkedResponse.StatusCode);
        Assert.Equal("succeeded",(await checkedResponse.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("status").GetString());
        Assert.Equal(1,factory.Cloud.Creates);Assert.Equal(1,factory.Cloud.Inspections);
    }
}
