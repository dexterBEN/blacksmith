using Blacksmith.Application.DTOs;
using Blacksmith.Application.Exceptions;
using Blacksmith.Application.Services;
using Blacksmith.Domain.Entities;
using Xunit;

namespace Blacksmith.Application.Tests;

public sealed class DesignServiceTests
{
    [Fact]
    public async Task Empty_design_lifecycle_trims_metadata_preserves_identity_and_forwards_cancellation()
    {
        var repository = new MemoryDesignRepository();
        var service = new DesignService(repository);
        using var cancellation = new CancellationTokenSource();
        var before = DateTime.UtcNow;
        var created = await service.CreateAsync(new CreateDesignRequest
        { Name = "  Canvas  ", Description = "  Description  " }, cancellation.Token);
        Assert.NotEqual(Guid.Empty, created.Id);
        Assert.Equal("Canvas", created.Name);
        Assert.Equal("Description", created.Description);
        Assert.Equal(created.CreatedAtUtc, created.UpdatedAtUtc);
        Assert.InRange(created.CreatedAtUtc, before, DateTime.UtcNow);
        Assert.Equal(DateTimeKind.Utc, created.CreatedAtUtc.Kind);
        Assert.Empty(Assert.Single(repository.Designs).Resources);

        var updated = await service.UpdateAsync(created.Id,
            new UpdateDesignRequest { Name = " Renamed ", Description = " " }, cancellation.Token);
        Assert.NotNull(updated);
        Assert.Equal(created.Id, updated.Id);
        Assert.Equal(created.CreatedAtUtc, updated.CreatedAtUtc);
        Assert.True(updated.UpdatedAtUtc >= created.UpdatedAtUtc);
        Assert.Equal("Renamed", updated.Name);
        Assert.Null(updated.Description);
        Assert.Equal(updated, await service.GetByIdAsync(created.Id, cancellation.Token));
        Assert.Equal(updated, Assert.Single(await service.ListAsync(cancellation.Token)));
        Assert.True(await service.DeleteAsync(created.Id, cancellation.Token));
        Assert.Empty(repository.Designs);
        Assert.Equal(3, repository.Saves);
        Assert.Equal(cancellation.Token, repository.LastToken);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("  ")]
    public async Task Invalid_names_do_not_persist(string? name)
    {
        var repository = new MemoryDesignRepository();
        var service = new DesignService(repository);
        await Assert.ThrowsAsync<DesignValidationException>(() => service.CreateAsync(
            new CreateDesignRequest { Name = name! }, default));
        await Assert.ThrowsAsync<DesignValidationException>(() => service.UpdateAsync(Guid.NewGuid(),
            new UpdateDesignRequest { Name = name! }, default));
        Assert.Empty(repository.Designs);
        Assert.Equal(0, repository.Saves);
    }

    [Fact]
    public async Task Overlong_names_are_rejected_before_persistence()
    {
        var repository = new MemoryDesignRepository();
        await Assert.ThrowsAsync<DesignValidationException>(() => new DesignService(repository)
            .CreateAsync(new CreateDesignRequest { Name = new string('x', 201) }, default));
        Assert.Equal(0, repository.Saves);
    }

    [Fact]
    public async Task Nonempty_design_cannot_be_removed()
    {
        var repository = new MemoryDesignRepository { ContainsResources = true };
        var design = new DesignEntity { Id = Guid.NewGuid(), Name = "In use" };
        repository.Designs.Add(design);
        var error = await Assert.ThrowsAsync<DesignDeletionConflictException>(() =>
            new DesignService(repository).DeleteAsync(design.Id, default));
        Assert.Equal("Cannot delete a design that contains resources.", error.Message);
        Assert.Same(design, Assert.Single(repository.Designs));
        Assert.Equal(0, repository.Saves);
    }

    [Fact]
    public async Task Missing_design_reads_updates_and_deletes_do_not_save()
    {
        var repository = new MemoryDesignRepository();
        var service = new DesignService(repository);
        Assert.Null(await service.GetByIdAsync(Guid.NewGuid(), default));
        Assert.Null(await service.UpdateAsync(Guid.NewGuid(), new UpdateDesignRequest { Name = "Valid" }, default));
        Assert.False(await service.DeleteAsync(Guid.NewGuid(), default));
        Assert.Equal(0, repository.Saves);
    }

    [Fact]
    public async Task Cancellation_reaches_repository()
    {
        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();
        var repository = new MemoryDesignRepository();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() =>
            new DesignService(repository).ListAsync(cancellation.Token));
        Assert.Equal(0, repository.Saves);
    }
}
