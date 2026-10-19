using Blacksmith.Application.Interfaces;
using Blacksmith.Application.Exceptions;
using Blacksmith.Domain.Entities;
using Blacksmith.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Npgsql;

namespace Blacksmith.Infrastructure.Repositories;

public sealed class EfResourceRepository(BlacksmithDbContext db) : IResourceRepository
{
    public async Task<IReadOnlyList<ResourceEntity>> ListByDesignIdAsync(Guid designId, CancellationToken ct) =>
        await db.Resources.AsNoTracking().Where(resource => resource.DesignId == designId)
            .OrderByDescending(resource => resource.CreatedAtUtc).ToListAsync(ct);
    public async Task<IReadOnlyList<ResourceEntity>> ListAsync(CancellationToken ct) =>
        await db.Resources.AsNoTracking().OrderByDescending(resource => resource.CreatedAtUtc).ToListAsync(ct);

    public Task<ResourceEntity?> GetByIdAsync(Guid id, CancellationToken ct) =>
        db.Resources.FirstOrDefaultAsync(resource => resource.Id == id, ct);

    public void Add(ResourceEntity resource) => db.Resources.Add(resource);

    public void Remove(ResourceEntity resource) => db.Resources.Remove(resource);

    public async Task SaveChangesAsync(CancellationToken ct)
    {
        try { await db.SaveChangesAsync(ct); }
        catch (DbUpdateException exception) when (exception.InnerException is PostgresException
        { SqlState: PostgresErrorCodes.ForeignKeyViolation, ConstraintName: BlacksmithDbContext.ResourceDesignForeignKey })
        {
            var resource = db.ChangeTracker.Entries<ResourceEntity>()
                .FirstOrDefault(entry => entry.State is EntityState.Added or EntityState.Modified);
            if (resource is null) throw;
            throw new DesignNotFoundException(resource.Entity.DesignId, exception);
        }
        catch (DbUpdateException exception) when (exception.InnerException is PostgresException
        { SqlState: PostgresErrorCodes.ForeignKeyViolation, ConstraintName: BlacksmithDbContext.ResourceTypeForeignKey })
        {
            var resource = db.ChangeTracker.Entries<ResourceEntity>().FirstOrDefault(entry =>
                (entry.State is EntityState.Added or EntityState.Modified) && entry.Entity.ResourceTypeId.HasValue);
            if (resource is null) throw;
            throw new ResourceTypeNotFoundException(resource.Entity.ResourceTypeId!.Value, exception);
        }
    }
}
