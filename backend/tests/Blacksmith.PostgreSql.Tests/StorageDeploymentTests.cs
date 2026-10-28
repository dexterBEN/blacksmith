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

    [PostgreSqlFact]
    public async Task Five_fresh_api_hosts_read_all_durable_states_without_cloud_calls_or_database_writes()
    {
        await Seed();
        var cases = new[] {
            (Bucket: "blacksmith-reopen-success", Status: "succeeded", Code: "verified"),
            (Bucket: "blacksmith-reopen-reject", Status: "failed", Code: "provider_rejected"),
            (Bucket: "blacksmith-reopen-lost", Status: "unknown", Code: "provider_timeout"),
            (Bucket: "blacksmith-reopen-pending", Status: "pending", Code: "deploying"),
            (Bucket: "blacksmith-reopen-expired", Status: "unknown", Code: "execution_interrupted"),
        };
        var ids = cases.Select(_ => (Resource: Guid.NewGuid(), Operation: Guid.NewGuid())).ToArray();
        var savedOnly = Guid.NewGuid();
        object Configuration(string bucket, int x, int y = 0) => new {
            name = "Cloud Storage", type = "gcp.storage.bucket",
            resourceTypeId = "10000000-0000-0000-0000-000000000002", x, y,
            configuration = new { schemaVersion = 1, configuration = new {
                projectId = "example-project-123", bucketName = bucket, location = "europe-west9"
            } }
        };
        using (var factory = new DeploymentApiFactory(o => o.UseNpgsql(ConnectionString))) {
            using var client = Client(factory);
            for (var i = 0; i < cases.Length; i++)
                Assert.Equal(HttpStatusCode.OK, (await Write(client, ids[i].Resource, ids[i].Operation,
                    Configuration(cases[i].Bucket, i))).StatusCode);
            using var save = new HttpRequestMessage(HttpMethod.Put,
                $"/designs/{LegacyDesign.Id}/resources/{savedOnly}") {
                Content = JsonContent.Create(Configuration("blacksmith-reopen-save-only", 5, 1))
            };
            save.Headers.TryAddWithoutValidation("If-None-Match", "*");
            Assert.Equal(HttpStatusCode.Created, (await client.SendAsync(save)).StatusCode);
            Assert.Equal(5, factory.Cloud.Creates);
            Assert.Equal(0, factory.Cloud.Inspections);
        }
        // Isolated SQL fixture states model an active execution and an interrupted
        // process. No production endpoint or schema change is introduced.
        await using (var db = CreateContext()) {
            for (var i = 3; i < 5; i++) {
                var operation = await db.StorageDeployments.SingleAsync(d => d.Id == ids[i].Operation);
                operation.Status = "pending";
                operation.Code = "deploying";
                operation.OwnershipVerified = false;
                operation.LeaseUntilUtc = DateTime.UtcNow.AddMinutes(i == 3 ? 10 : -10);
            }
            await db.SaveChangesAsync();
        }
        async Task<string[]> Fingerprints() {
            var hashes = new List<string>();
            foreach (var table in new[] { "designs", "resources", "resource_configurations", "storage_deployments", "storage_deployment_attempts" })
                hashes.Add(await Scalar<string>($"SELECT md5(COALESCE(string_agg(row_to_json(t)::text, '' ORDER BY row_to_json(t)::text), '')) FROM {table} t"));
            return hashes.ToArray();
        }
        var before = await Fingerprints();
        string? baseline = null;
        for (var cycle = 0; cycle < 5; cycle++) {
            using var factory = new DeploymentApiFactory(o => o.UseNpgsql(ConnectionString));
            using var client = Client(factory);
            var records = await client.GetFromJsonAsync<JsonElement>(
                $"/designs/{LegacyDesign.Id}/resources?include=configuration");
            Assert.Equal(6, records.GetArrayLength());
            var snapshot = string.Join("\n", records.EnumerateArray()
                .OrderBy(r => r.GetProperty("id").GetGuid()).Select(r => r.GetRawText()));
            baseline ??= snapshot;
            Assert.Equal(baseline, snapshot);
            for (var i = 0; i < cases.Length; i++) {
                var operation = await client.GetFromJsonAsync<JsonElement>(Route(ids[i].Resource, ids[i].Operation));
                Assert.Equal(cases[i].Status, operation.GetProperty("status").GetString());
                Assert.Equal(cases[i].Code, operation.GetProperty("code").GetString());
                var record = records.EnumerateArray().Single(r => r.GetProperty("id").GetGuid() == ids[i].Resource);
                Assert.Equal(ids[i].Operation, record.GetProperty("deployment").GetProperty("id").GetGuid());
                Assert.Equal(cases[i].Status, record.GetProperty("deployment").GetProperty("status").GetString());
                Assert.Equal(i, record.GetProperty("x").GetInt32());
                Assert.Equal(0, record.GetProperty("y").GetInt32());
                Assert.Equal(cases[i].Bucket, record.GetProperty("configuration").GetProperty("configuration").GetProperty("bucketName").GetString());
            }
            Assert.False(records.EnumerateArray().Single(r => r.GetProperty("id").GetGuid() == savedOnly).TryGetProperty("deployment", out _));
            Assert.Equal(0, factory.Cloud.Creates);
            Assert.Equal(0, factory.Cloud.Inspections);
            Assert.Equal(before, await Fingerprints());
        }
        Assert.Equal(6L, await Scalar<long>("SELECT count(*) FROM resources"));
        Assert.Equal(6L, await Scalar<long>("SELECT count(*) FROM resource_configurations"));
        Assert.Equal(5L, await Scalar<long>("SELECT count(*) FROM storage_deployments"));
        Assert.Equal(5L, await Scalar<long>("SELECT count(*) FROM storage_deployment_attempts"));
    }
}
