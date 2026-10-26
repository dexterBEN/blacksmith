using Blacksmith.Application.Interfaces;
using Blacksmith.Application.Exceptions;
using Blacksmith.Domain.Entities;
using Blacksmith.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;
using Npgsql;

namespace Blacksmith.Infrastructure.Repositories;

public sealed class EfResourceRepository(BlacksmithDbContext db) : IResourceRepository, IAsyncDisposable, IDisposable
{
    private IDbContextTransaction? _transaction;
    public async Task<IReadOnlyList<ResourceEntity>> ListByDesignIdAsync(Guid designId, CancellationToken ct) =>
        await db.Resources.AsNoTracking().Where(resource => resource.DesignId == designId)
            .OrderByDescending(resource => resource.CreatedAtUtc).ToListAsync(ct);
    public async Task<IReadOnlyList<ResourceEntity>> ListAsync(CancellationToken ct) =>
        await db.Resources.AsNoTracking().OrderByDescending(resource => resource.CreatedAtUtc).ToListAsync(ct);

    public Task<ResourceEntity?> GetByIdAsync(Guid id, CancellationToken ct) =>
        db.Resources.FirstOrDefaultAsync(resource => resource.Id == id, ct);

    public async Task<ResourceEntity?> GetForUpdateAsync(Guid id, CancellationToken ct)
    {
        _transaction ??= await db.Database.BeginTransactionAsync(ct);
        // Serialize configuration and metadata-type writes on the existing parent.
        // The SQLite HTTP fixture uses its ordinary transaction instead.
        return db.Database.IsNpgsql()
            ? await db.Resources.FromSqlInterpolated($"""SELECT * FROM resources WHERE "Id"={id} FOR UPDATE""").SingleOrDefaultAsync(ct)
            : await GetByIdAsync(id, ct);
    }

    public Task<ResourceConfiguration?> GetConfigurationAsync(Guid resourceId, CancellationToken ct) =>
        db.ResourceConfigurations.FirstOrDefaultAsync(configuration => configuration.ResourceId == resourceId, ct);

    public Task<ResourceEntity?> GetAggregateAsync(Guid id, CancellationToken ct) =>
        db.Resources.AsNoTracking().Include(x => x.Configuration).Include(x => x.ResourceType).SingleOrDefaultAsync(x => x.Id == id, ct);

    public async Task<IReadOnlyList<ResourceEntity>> ListAggregatesAsync(Guid designId, CancellationToken ct) =>
        await db.Resources.AsNoTracking().Include(x => x.Configuration).Include(x => x.ResourceType)
            .Where(x => x.DesignId == designId).OrderBy(x => x.Y).ThenBy(x => x.X).ThenBy(x => x.Id).ToListAsync(ct);

    public Task<bool> HasConfigurationAsync(Guid resourceId, CancellationToken ct) =>
        db.ResourceConfigurations.AnyAsync(configuration => configuration.ResourceId == resourceId, ct);

    public void AddConfiguration(ResourceConfiguration configuration) => db.ResourceConfigurations.Add(configuration);

    public void Add(ResourceEntity resource) => db.Resources.Add(resource);

    public void Remove(ResourceEntity resource) => db.Resources.Remove(resource);

    public async Task SaveChangesAsync(CancellationToken ct)
    {
        try
        {
            await db.SaveChangesAsync(ct);
            if (_transaction is not null) await _transaction.CommitAsync(ct);
        }
        catch (DbUpdateConcurrencyException)
        {
            throw new ResourceConflictException("revision_conflict", "The Resource changed. Read it before retrying.", 412);
        }
        catch (DbUpdateException exception) when (exception.InnerException is PostgresException
            { SqlState: PostgresErrorCodes.UniqueViolation, ConstraintName: BlacksmithDbContext.ResourceTileIndex })
        {
            throw new ResourceConflictException("tile_occupied", "Another Resource occupies this Design tile.");
        }
        catch (DbUpdateException exception) when (exception.InnerException is PostgresException
            { SqlState: PostgresErrorCodes.UniqueViolation, ConstraintName: "PK_resources" })
        {
            throw new ResourceConflictException("resource_exists", "The Resource ID already exists. Read it before reconciling this intent.", 412);
        }
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
        finally { await DisposeAsync(); }
    }

    public async ValueTask DisposeAsync()
    {
        if (_transaction is null) return;
        await _transaction.DisposeAsync(); // Uncommitted validation failures roll back on scope disposal.
        _transaction = null;
    }

    public void Dispose()
    {
        _transaction?.Dispose();
        _transaction = null;
    }
}
