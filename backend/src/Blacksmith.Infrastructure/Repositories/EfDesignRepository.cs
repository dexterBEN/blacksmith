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

    public async Task<bool> DeleteUndeployedAsync(Guid id, CancellationToken ct)
    {
        await using var transaction = await db.Database.BeginTransactionAsync(ct);
        var design = await GetByIdAsync(id, ct);
        if (design is null) return false;

        // All outcomes count as history, including failed, pending and unknown.
        if (await db.StorageDeployments.AnyAsync(x => x.DesignId == id || x.Resource.DesignId == id, ct))
            throw new DesignDeletionConflictException(id);

        var resources = await db.Resources.Where(x => x.DesignId == id).ToListAsync(ct);
        db.Resources.RemoveRange(resources);
        db.Designs.Remove(design);
        try
        {
            // One SaveChanges transaction; configuration rows cascade from resources.
            // Restrictive FKs remain the final guard against concurrent inserts/deployments.
            await db.SaveChangesAsync(ct);
            await transaction.CommitAsync(ct);
            return true;
        }
        catch (DbUpdateConcurrencyException exception)
        {
            throw new DesignDeletionConflictException(id, exception);
        }
        catch (DbUpdateException exception) when (exception.InnerException is PostgresException
            { SqlState: PostgresErrorCodes.ForeignKeyViolation, ConstraintName:
                BlacksmithDbContext.ResourceDesignForeignKey or "FK_storage_deployments_resources_resource_id" })
        {
            throw new DesignDeletionConflictException(id, exception);
        }
    }

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

    public async Task SaveChangesAsync(CancellationToken ct) => await db.SaveChangesAsync(ct);
}
