// Native E2E fixture only. Actual API/EF/PostgreSQL, injected cloud fake, no ADC.
using System.Text.Json;
using Blacksmith.Infrastructure.Persistence;
using Blacksmith.TestSupport;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.Hosting;
using Microsoft.EntityFrameworkCore;
using Npgsql;

var configured=Environment.GetEnvironmentVariable("ConnectionStrings__BlacksmithDb")??throw new InvalidOperationException("Existing container DB configuration required.");
var admin=new NpgsqlConnectionStringBuilder(configured){Database="postgres",Pooling=false};
var name="blacksmith_front_smoke_"+Guid.NewGuid().ToString("N");
var connection=new NpgsqlConnectionStringBuilder(admin.ConnectionString){Database=name,Pooling=false};
var directory=Path.GetFullPath(args[0]);var port=int.Parse(args[1]);
if(port is <1024 or >65535)throw new ArgumentException("Nonprivileged port required.");
await using var administrative=new NpgsqlConnection(admin.ConnectionString);await administrative.OpenAsync();
await using(var create=new NpgsqlCommand($"CREATE DATABASE \"{name}\"",administrative))await create.ExecuteNonQueryAsync();
try {
    await using(var db=new BlacksmithDbContext(new DbContextOptionsBuilder<BlacksmithDbContext>().UseNpgsql(connection.ConnectionString).Options))await db.Database.MigrateAsync();
    using var factory=new DeploymentApiFactory(o=>o.UseNpgsql(connection.ConnectionString));
    using var hosted=factory.WithWebHostBuilder(b=>b.UseContentRoot(Path.Combine(directory,"src/CloudServices.Api")));
    using var client=hosted.CreateClient(new WebApplicationFactoryClientOptions{BaseAddress=new("https://localhost"),AllowAutoRedirect=false});
    var builder=WebApplication.CreateBuilder();builder.WebHost.UseUrls($"http://0.0.0.0:{port}");
    await using var app=builder.Build();
    app.MapGet("/__test/deployment-provider",async()=> {
        await using var db=new BlacksmithDbContext(new DbContextOptionsBuilder<BlacksmithDbContext>().UseNpgsql(connection.ConnectionString).Options);
        return new {fakeProvider=true,creates=factory.Cloud.Creates,inspections=factory.Cloud.Inspections,buckets=factory.Cloud.Buckets,
            resources=await db.Resources.CountAsync(),configurations=await db.ResourceConfigurations.CountAsync(),
            operations=await db.StorageDeployments.CountAsync(),attempts=await db.StorageDeploymentAttempts.CountAsync()};
    });
    app.Map("/{**path}",async (HttpContext context)=> {
        using var request=new HttpRequestMessage(new HttpMethod(context.Request.Method),context.Request.Path+context.Request.QueryString);
        if(context.Request.ContentLength>0)request.Content=new StreamContent(context.Request.Body);
        foreach(var header in context.Request.Headers) {
            if(header.Key.Equals("Host",StringComparison.OrdinalIgnoreCase))continue;
            if(!request.Headers.TryAddWithoutValidation(header.Key,header.Value.ToArray()))request.Content?.Headers.TryAddWithoutValidation(header.Key,header.Value.ToArray());
        }
        using var response=await client.SendAsync(request,context.RequestAborted);
        context.Response.StatusCode=(int)response.StatusCode;
        foreach(var header in response.Headers.Concat(response.Content.Headers))
            if(header.Key is not ("Transfer-Encoding" or "Content-Length"))context.Response.Headers[header.Key]=header.Value.ToArray();
        await response.Content.CopyToAsync(context.Response.Body);
    });
    await app.StartAsync();
    await File.WriteAllTextAsync(Path.Combine(directory,"metadata.json"),JsonSerializer.Serialize(new {database=name,port,fakeProvider=true}));
    Console.WriteLine($"BLACKSMITH_DEPLOYMENT_BACKEND_STARTED database={name} port={port} provider=fake");
    while(!File.Exists(Path.Combine(directory,"stop")))await Task.Delay(250);
    await app.StopAsync();
} finally {
    NpgsqlConnection.ClearAllPools();
    await using var drop=new NpgsqlCommand($"DROP DATABASE \"{name}\" WITH (FORCE)",administrative);await drop.ExecuteNonQueryAsync();
    Console.WriteLine($"BLACKSMITH_DEPLOYMENT_BACKEND_CLEANED database={name}");
}
