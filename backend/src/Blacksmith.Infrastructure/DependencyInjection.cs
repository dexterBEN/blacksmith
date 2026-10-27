using Blacksmith.Application.Interfaces;
using Blacksmith.Infrastructure.Persistence;
using Blacksmith.Infrastructure.Repositories;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;

namespace Blacksmith.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddBlacksmithInfrastructure(
        this IServiceCollection services, string? connectionString)
    {
        services.AddDbContext<BlacksmithDbContext>(options => options.UseNpgsql(connectionString));
        services.AddScoped<IResourceRepository, EfResourceRepository>();
        services.AddScoped<IStorageDeploymentStore, EfStorageDeploymentStore>();
        services.AddScoped<IDesignRepository, EfDesignRepository>();
        services.AddScoped<IResourceTypeRepository, EfResourceTypeRepository>();
        services.AddScoped<IDatabaseHealthCheck, PostgreSqlDatabaseHealthCheck>();
        return services;
    }
}
