namespace Blacksmith.Application.Interfaces;

public interface IDatabaseHealthCheck
{
    Task<DateTime> GetDatabaseTimeAsync(CancellationToken ct);
}
