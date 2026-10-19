using Blacksmith.Application.Interfaces;
using Blacksmith.Domain.Entities;

namespace Blacksmith.Application.Tests;

internal sealed class MemoryDesignRepository : IDesignRepository
{
    public List<DesignEntity> Designs { get; } = [];
    public bool ContainsResources { get; set; }
    public int Saves { get; private set; }
    public int LegacyEnsures { get; private set; }
    public CancellationToken LastToken { get; private set; }

    private void Check(CancellationToken ct) { ct.ThrowIfCancellationRequested(); LastToken = ct; }
    public Task<IReadOnlyList<DesignEntity>> ListAsync(CancellationToken ct)
    {
        Check(ct);
        return Task.FromResult<IReadOnlyList<DesignEntity>>(Designs.OrderByDescending(x => x.CreatedAtUtc).ToArray());
    }
    public Task<DesignEntity?> GetByIdAsync(Guid id, CancellationToken ct)
    {
        Check(ct);
        return Task.FromResult(Designs.FirstOrDefault(x => x.Id == id));
    }
    public Task<bool> ExistsAsync(Guid id, CancellationToken ct)
    {
        Check(ct);
        return Task.FromResult(Designs.Any(x => x.Id == id));
    }
    public Task<bool> HasResourcesAsync(Guid id, CancellationToken ct)
    {
        Check(ct);
        return Task.FromResult(ContainsResources);
    }
    public Task EnsureLegacyDesignAsync(CancellationToken ct)
    {
        Check(ct);
        LegacyEnsures++;
        if (Designs.All(x => x.Id != LegacyDesign.Id))
            Designs.Add(new DesignEntity { Id = LegacyDesign.Id, Name = LegacyDesign.Name });
        return Task.CompletedTask;
    }
    public void Add(DesignEntity design) => Designs.Add(design);
    public void Remove(DesignEntity design) => Designs.Remove(design);
    public Task SaveChangesAsync(CancellationToken ct)
    {
        Check(ct);
        Saves++;
        return Task.CompletedTask;
    }
}
