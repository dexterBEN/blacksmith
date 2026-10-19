using Blacksmith.Application.DTOs;

namespace Blacksmith.Application.Interfaces;

public interface IDesignService
{
    Task<DesignResponse> CreateAsync(CreateDesignRequest request, CancellationToken ct);
    Task<IReadOnlyList<DesignResponse>> ListAsync(CancellationToken ct);
    Task<DesignResponse?> GetByIdAsync(Guid id, CancellationToken ct);
    Task<DesignResponse?> UpdateAsync(Guid id, UpdateDesignRequest request, CancellationToken ct);
    Task<bool> DeleteAsync(Guid id, CancellationToken ct);
}
