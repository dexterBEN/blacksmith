using CloudServices.Core;
using Providers.GoogleCloud;
using Npgsql;
using CloudServices.Api.Data;
using Microsoft.EntityFrameworkCore;

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
builder.Services.AddScoped<ICloudStorageService, GoogleCloudStorageService>();

var cs = builder.Configuration.GetConnectionString("BlacksmithDb");
builder.Services.AddDbContext<BlacksmithDbContext>(opt => opt.UseNpgsql(cs));

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
app.MapGet("/db/ping", async (IConfiguration config) =>
{
    var cs = config.GetConnectionString("BlacksmithDb");

    await using var conn = new NpgsqlConnection(cs);
    await conn.OpenAsync();

    await using var cmd = new NpgsqlCommand("select now()", conn);
    var dbTime = await cmd.ExecuteScalarAsync();

    return Results.Ok(new
    {
        status = "ok",
        dbTime
    });
});

app.Run();