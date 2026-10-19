using Blacksmith.Application.Interfaces;
using Blacksmith.Domain.Entities;

namespace Blacksmith.Application.Tests;

internal sealed class MemoryResourceTypeRepository : IResourceTypeRepository
{
    public List<ResourceTypeEntity> Types { get; } = [];
    public CancellationToken LastToken { get; private set; }

    private void Check(CancellationToken ct) { ct.ThrowIfCancellationRequested(); LastToken = ct; }
    public Task<IReadOnlyList<ResourceTypeEntity>> ListAsync(CancellationToken ct)
    {
        Check(ct);
        return Task.FromResult<IReadOnlyList<ResourceTypeEntity>>(Types.OrderBy(x => x.Code, StringComparer.Ordinal).ToArray());
    }
    public Task<ResourceTypeEntity?> GetByIdAsync(Guid id, CancellationToken ct)
    {
        Check(ct);
        return Task.FromResult(Types.FirstOrDefault(x => x.Id == id));
    }
    public Task<ResourceTypeEntity?> GetByCodeAsync(string code, CancellationToken ct)
    {
        Check(ct);
        return Task.FromResult(Types.FirstOrDefault(x => x.Code == code));
    }
}
