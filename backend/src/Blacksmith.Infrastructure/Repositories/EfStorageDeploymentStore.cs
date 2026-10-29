using System.Buffers.Binary;
using System.Security.Cryptography;
using Blacksmith.Application.Interfaces;
using Blacksmith.Domain.Entities;
using Blacksmith.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;

namespace Blacksmith.Infrastructure.Repositories;

public sealed class EfStorageDeploymentStore(BlacksmithDbContext db) : IStorageDeploymentStore, IStorageDeletionStore
{
    public async Task<IDeploymentTransaction> LockResourceAsync(Guid resourceId, CancellationToken ct)
    {
        db.ChangeTracker.Clear(); // Each claim/completion must observe the latest committed state.
        var transaction = await db.Database.BeginTransactionAsync(ct);
        if (db.Database.IsNpgsql())
        {
            var key = BinaryPrimitives.ReadInt64LittleEndian(SHA256.HashData(resourceId.ToByteArray()));
            await db.Database.ExecuteSqlInterpolatedAsync($"SELECT pg_advisory_xact_lock({key})", ct);
            await db.Database.ExecuteSqlInterpolatedAsync($"""SELECT "Id" FROM resources WHERE "Id"={resourceId} FOR UPDATE""", ct);
        }
        return new Transaction(db, transaction);
    }
    public Task<StorageDeployment?> FindAsync(Guid id, CancellationToken ct) => db.StorageDeployments.FirstOrDefaultAsync(x => x.Id == id, ct);
    public Task<StorageDeployment?> FirstForResourceAsync(Guid id, CancellationToken ct) =>
        db.StorageDeployments.Where(x => x.ResourceId == id).OrderBy(x => x.CreatedAtUtc).ThenBy(x => x.Id).FirstOrDefaultAsync(ct);
    public Task<StorageDeployment?> ForRevisionAsync(Guid id, long revision, CancellationToken ct) =>
        db.StorageDeployments.SingleOrDefaultAsync(x => x.ResourceId == id && x.ResourceRevision == revision, ct);
    public Task<StorageDeploymentAttempt?> FindAttemptAsync(Guid id, CancellationToken ct) =>
        db.StorageDeploymentAttempts.FirstOrDefaultAsync(x => x.Id == id, ct);
    public void Add(StorageDeployment operation) => db.StorageDeployments.Add(operation);
    public void AddAttempt(StorageDeploymentAttempt attempt) => db.StorageDeploymentAttempts.Add(attempt);

    public Task<StorageDeletion?> FindDeletionAsync(Guid id, CancellationToken ct) =>
        db.StorageDeletions.SingleOrDefaultAsync(x => x.ResourceId == id, ct);
    public Task<ResourceEntity?> DeletionResourceAsync(Guid id, CancellationToken ct) =>
        db.Resources.Include(x => x.Deployments).SingleOrDefaultAsync(x => x.Id == id, ct);
    public Task<bool> HasDeletionAttemptAsync(Guid id, CancellationToken ct) =>
        db.StorageDeletionAttempts.AnyAsync(x => x.Id == id, ct);
    public void AddDeletion(StorageDeletion deletion) => db.StorageDeletions.Add(deletion);
    public void AddDeletionAttempt(StorageDeletionAttempt attempt) => db.StorageDeletionAttempts.Add(attempt);
    public async Task RemoveDeletedResourceAsync(Guid id, CancellationToken ct)
    {
        var history = await db.StorageDeployments.Include(x => x.Attempts).Where(x => x.ResourceId == id).ToListAsync(ct);
        db.StorageDeploymentAttempts.RemoveRange(history.SelectMany(x => x.Attempts));
        db.StorageDeployments.RemoveRange(history);
        var resource = await db.Resources.SingleOrDefaultAsync(x => x.Id == id, ct);
        if (resource is not null) db.Resources.Remove(resource);
    }

    private sealed class Transaction(BlacksmithDbContext db, IDbContextTransaction transaction) : IDeploymentTransaction
    {
        public async Task CommitAsync(CancellationToken ct) { await db.SaveChangesAsync(ct); await transaction.CommitAsync(ct); }
        public ValueTask DisposeAsync() => transaction.DisposeAsync();
    }
}
