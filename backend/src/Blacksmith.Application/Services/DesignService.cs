using Blacksmith.Application.DTOs;
using Blacksmith.Application.Exceptions;
using Blacksmith.Application.Interfaces;
using Blacksmith.Domain.Entities;

namespace Blacksmith.Application.Services;

public sealed class DesignService(IDesignRepository repository) : IDesignService
{
    public async Task<DesignResponse> CreateAsync(CreateDesignRequest request, CancellationToken ct)
    {
        Validate(request.Name);
        var now = DateTime.UtcNow;
        var design = new DesignEntity
        {
            Id = Guid.NewGuid(), Name = request.Name.Trim(), Description = NormalizeDescription(request.Description),
            CreatedAtUtc = now, UpdatedAtUtc = now
        };
        repository.Add(design);
        await repository.SaveChangesAsync(ct);
        return ToResponse(design);
    }

    public async Task<IReadOnlyList<DesignResponse>> ListAsync(CancellationToken ct) =>
        (await repository.ListAsync(ct)).Select(ToResponse).ToArray();

    public async Task<DesignResponse?> GetByIdAsync(Guid id, CancellationToken ct)
    {
        var design = await repository.GetByIdAsync(id, ct);
        return design is null ? null : ToResponse(design);
    }

    public async Task<DesignResponse?> UpdateAsync(Guid id, UpdateDesignRequest request, CancellationToken ct)
    {
        Validate(request.Name);
        var design = await repository.GetByIdAsync(id, ct);
        if (design is null) return null;
        design.Name = request.Name.Trim();
        design.Description = NormalizeDescription(request.Description);
        design.UpdatedAtUtc = DateTime.UtcNow;
        await repository.SaveChangesAsync(ct);
        return ToResponse(design);
    }

    public async Task<bool> DeleteAsync(Guid id, CancellationToken ct)
    {
        var design = await repository.GetByIdAsync(id, ct);
        if (design is null) return false;
        if (await repository.HasResourcesAsync(id, ct)) throw new DesignDeletionConflictException(id);
        repository.Remove(design);
        // Infrastructure also translates a concurrent insert rejected by the restrictive FK.
        await repository.SaveChangesAsync(ct);
        return true;
    }

    private static void Validate(string name)
    {
        if (string.IsNullOrWhiteSpace(name)) throw new DesignValidationException("Name is required");
        if (name.Trim().Length > 200) throw new DesignValidationException("Name must be at most 200 characters");
    }

    private static string? NormalizeDescription(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();

    private static DesignResponse ToResponse(DesignEntity design) => new(
        design.Id, design.Name, design.Description, design.CreatedAtUtc, design.UpdatedAtUtc);
}
