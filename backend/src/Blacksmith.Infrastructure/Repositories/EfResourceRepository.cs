using Blacksmith.Application.Interfaces;
using Blacksmith.Domain.Entities;
using Blacksmith.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Blacksmith.Infrastructure.Repositories;

public sealed class EfResourceRepository(BlacksmithDbContext db) : IResourceRepository
{
    public async Task<IReadOnlyList<ResourceEntity>> ListAsync(CancellationToken ct) =>
        await db.Resources.AsNoTracking().OrderByDescending(resource => resource.CreatedAtUtc).ToListAsync(ct);

    public Task<ResourceEntity?> GetByIdAsync(Guid id, CancellationToken ct) =>
        db.Resources.FirstOrDefaultAsync(resource => resource.Id == id, ct);

    public void Add(ResourceEntity resource) => db.Resources.Add(resource);

    public void Remove(ResourceEntity resource) => db.Resources.Remove(resource);

    public async Task SaveChangesAsync(CancellationToken ct) => await db.SaveChangesAsync(ct);
}
