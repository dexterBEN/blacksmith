using Blacksmith.Application.Services;
using Blacksmith.Domain.Entities;
using Xunit;

namespace Blacksmith.Application.Tests;

public sealed class ResourceTypeServiceTests
{
    [Fact]
    public async Task Catalog_reads_return_dto_snapshots_and_forward_cancellation()
    {
        var repository = new MemoryResourceTypeRepository();
        var entity = new ResourceTypeEntity { Id = Guid.NewGuid(), Code = "storage", DisplayName = "Storage", Category = "Storage" };
        repository.Types.Add(entity);
        var service = new ResourceTypeService(repository);
        using var cancellation = new CancellationTokenSource();
        var listed = Assert.Single(await service.ListAsync(cancellation.Token));
        var found = await service.GetByIdAsync(entity.Id, cancellation.Token);
        Assert.Equal(listed, found);
        Assert.Null(await service.GetByIdAsync(Guid.NewGuid(), cancellation.Token));
        entity.DisplayName = "Changed later";
        Assert.Equal("Storage", listed.DisplayName);
        Assert.Equal(cancellation.Token, repository.LastToken);
    }

    [Fact]
    public async Task Catalog_cancellation_is_not_swallowed()
    {
        var repository = new MemoryResourceTypeRepository();
        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() =>
            new ResourceTypeService(repository).ListAsync(cancellation.Token));
    }
}
