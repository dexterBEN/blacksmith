using CloudServices.Core;
using Providers.GoogleCloud;
using Blacksmith.Application.Interfaces;
using Blacksmith.Application.Services;
using Blacksmith.Infrastructure;
using CloudServices.Api;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

// CORS
builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowAll", policy =>
    {
        policy.AllowAnyOrigin()
              .AllowAnyMethod()
              .AllowAnyHeader();
    });
});

// provider GCP injection ICloudStorageService
builder.Services.AddScoped<ICloudStorageService>(_ => new GoogleCloudStorageService());
builder.Services.AddScoped<ICloudBucketProvisioner>(_ => new GoogleCloudStorageService());
builder.Services.AddSingleton<DeploymentPolicy>();
builder.Services.AddSingleton<IDeploymentTargetPolicy>(services => services.GetRequiredService<DeploymentPolicy>());
builder.Services.AddScoped<IStorageDeploymentService, StorageDeploymentService>();
builder.Services.AddScoped<ICloudBucketDeleter>(_ => new GoogleCloudStorageService());
builder.Services.AddScoped<IStorageDeletionService, StorageDeletionService>();

var cs = builder.Configuration.GetConnectionString("BlacksmithDb");
builder.Services.AddBlacksmithInfrastructure(cs);
builder.Services.AddScoped<IResourceService, ResourceService>();
builder.Services.AddScoped<IResourceConfigurationService, ResourceConfigurationService>();
builder.Services.AddScoped<IDesignService, DesignService>();
builder.Services.AddScoped<IResourceTypeService, ResourceTypeService>();

var app = builder.Build();

app.UseCors("AllowAll");

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseHttpsRedirection();
app.UseAuthorization();
app.MapControllers();

/* ===========================
 * DB PING ENDPOINT (TEST)
 * =========================== */
app.MapGet("/db/ping", async (IDatabaseHealthCheck database, CancellationToken ct) =>
{
    var dbTime = await database.GetDatabaseTimeAsync(ct);

    return Results.Ok(new
    {
        status = "ok",
        dbTime
    });
});

app.Run();

// Expose the entry point to the in-process HTTP contract tests.
public partial class Program { }
