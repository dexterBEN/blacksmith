using Blacksmith.Application.Interfaces;
using Blacksmith.Domain.Entities;
using Blacksmith.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace Blacksmith.Infrastructure.Repositories;

public sealed class EfResourceTypeRepository(BlacksmithDbContext db) : IResourceTypeRepository
{
    public async Task<IReadOnlyList<ResourceTypeEntity>> ListAsync(CancellationToken ct) =>
        await db.ResourceTypes.AsNoTracking().OrderBy(type => type.Code).ToListAsync(ct);

    public Task<ResourceTypeEntity?> GetByIdAsync(Guid id, CancellationToken ct) =>
        db.ResourceTypes.AsNoTracking().FirstOrDefaultAsync(type => type.Id == id, ct);

    public Task<ResourceTypeEntity?> GetByCodeAsync(string code, CancellationToken ct) =>
        db.ResourceTypes.AsNoTracking().FirstOrDefaultAsync(type => type.Code == code, ct);
}
