using Blacksmith.Application.Exceptions;
using Blacksmith.Application.Interfaces;
using Blacksmith.Domain.Entities;
using Blacksmith.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Npgsql;

namespace Blacksmith.Infrastructure.Repositories;

public sealed class EfDesignRepository(BlacksmithDbContext db) : IDesignRepository
{
    public async Task<IReadOnlyList<DesignEntity>> ListAsync(CancellationToken ct) =>
        await db.Designs.AsNoTracking().OrderByDescending(design => design.CreatedAtUtc).ToListAsync(ct);

    public Task<DesignEntity?> GetByIdAsync(Guid id, CancellationToken ct) =>
        db.Designs.FirstOrDefaultAsync(design => design.Id == id, ct);

    public Task<bool> ExistsAsync(Guid id, CancellationToken ct) =>
        db.Designs.AnyAsync(design => design.Id == id, ct);

    public Task<bool> HasResourcesAsync(Guid id, CancellationToken ct) =>
        db.Resources.AnyAsync(resource => resource.DesignId == id, ct);

    public async Task EnsureLegacyDesignAsync(CancellationToken ct)
    {
        var now = DateTime.UtcNow;
        // Atomic and idempotent even if several legacy clients create their first resource together.
        // Do not overwrite a name/description edited by the user.
        await db.Database.ExecuteSqlInterpolatedAsync($"""
            INSERT INTO designs ("Id", "Name", "Description", created_at_utc, updated_at_utc)
            VALUES ({LegacyDesign.Id}, {LegacyDesign.Name}, {LegacyDesign.Description}, {now}, {now})
            ON CONFLICT ("Id") DO NOTHING
            """, ct);
    }

    public void Add(DesignEntity design) => db.Designs.Add(design);
    public void Remove(DesignEntity design) => db.Designs.Remove(design);

    public async Task SaveChangesAsync(CancellationToken ct)
    {
        try { await db.SaveChangesAsync(ct); }
        catch (DbUpdateException exception) when (exception.InnerException is PostgresException
        { SqlState: PostgresErrorCodes.ForeignKeyViolation, ConstraintName: BlacksmithDbContext.ResourceDesignForeignKey })
        {
            var deleted = db.ChangeTracker.Entries<DesignEntity>()
                .FirstOrDefault(entry => entry.State == EntityState.Deleted);
            if (deleted is null) throw;
            throw new DesignDeletionConflictException(deleted.Entity.Id, exception);
        }
    }
}
