using Blacksmith.Application.DTOs;
using Blacksmith.Application.Exceptions;
using Blacksmith.Application.Interfaces;
using Blacksmith.Application.Services;
using Blacksmith.Domain.Entities;
using Xunit;

namespace Blacksmith.Application.Tests;

public sealed class ResourceServiceTests
{
    [Fact]
    public async Task Create_trims_names_preserves_coordinates_and_saves_without_cloud_work()
    {
        var repository = new MemoryResourceRepository();
        var service = new ResourceService(repository, new MemoryDesignRepository());
        using var cancellation = new CancellationTokenSource();
        var before = DateTime.UtcNow;

        var result = await service.CreateAsync(new CreateResourceRequest
        { Name = "  Example  ", Type = "  gcp.storage.bucket  ", X = -4, Y = 9 }, cancellation.Token);

        var entity = Assert.Single(repository.Resources);
        Assert.NotEqual(Guid.Empty, result.Id);
        Assert.Equal(LegacyDesign.Id, entity.DesignId);
        Assert.Equal(entity.Id, result.Id);
        Assert.Equal("Example", result.Name);
        Assert.Equal("gcp.storage.bucket", result.Type);
        Assert.Equal(-4, result.X);
        Assert.Equal(9, result.Y);
        Assert.Equal(DateTimeKind.Utc, result.CreatedAtUtc.Kind);
        Assert.InRange(result.CreatedAtUtc, before, DateTime.UtcNow);
        Assert.Equal(1, repository.Saves);
        Assert.Equal(cancellation.Token, repository.LastToken);
    }

    [Theory]
    [InlineData("", "bucket", "Name is required")]
    [InlineData("   ", "bucket", "Name is required")]
    [InlineData("valid", "", "Type is required")]
    [InlineData("valid", "   ", "Type is required")]
    [InlineData("", "", "Name is required")]
    public async Task Invalid_writes_do_not_lookup_or_persist(string name, string type, string expected)
    {
        var repository = new MemoryResourceRepository();
        var service = new ResourceService(repository, new MemoryDesignRepository());

        var createError = await Assert.ThrowsAsync<ResourceValidationException>(() =>
            service.CreateAsync(new CreateResourceRequest { Name = name, Type = type }, default));
        var updateError = await Assert.ThrowsAsync<ResourceValidationException>(() =>
            service.UpdateAsync(Guid.NewGuid(), new UpdateResourceRequest { Name = name, Type = type }, default));

        Assert.Equal(expected, createError.Message);
        Assert.Equal(expected, updateError.Message);
        Assert.Empty(repository.Resources);
        Assert.Equal(0, repository.Lookups);
        Assert.Equal(0, repository.Saves);
    }

    [Fact]
    public async Task Update_changes_only_mutable_fields_and_keeps_identity_and_creation_time()
    {
        var repository = new MemoryResourceRepository();
        var entity = new ResourceEntity { Id = Guid.NewGuid(), DesignId = Guid.NewGuid(), Name = "Before", Type = "before",
            CreatedAtUtc = new DateTime(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc) };
        repository.Resources.Add(entity);
        var service = new ResourceService(repository, new MemoryDesignRepository());
        using var cancellation = new CancellationTokenSource();

        var result = await service.UpdateAsync(entity.Id,
            new UpdateResourceRequest { Name = " After ", Type = " after ", X = 12, Y = -8 }, cancellation.Token);

        Assert.NotNull(result);
        Assert.Equal(entity.Id, result.Id);
        Assert.Equal(entity.CreatedAtUtc, result.CreatedAtUtc);
        Assert.NotEqual(Guid.Empty, entity.DesignId);
        Assert.Equal("After", result.Name);
        Assert.Equal("after", result.Type);
        Assert.Equal(12, result.X);
        Assert.Equal(-8, result.Y);
        Assert.Equal(1, repository.Saves);
        Assert.Equal(cancellation.Token, repository.LastToken);
    }

    [Fact]
    public async Task Missing_resources_do_not_save_for_update_or_delete()
    {
        var repository = new MemoryResourceRepository();
        var service = new ResourceService(repository, new MemoryDesignRepository());

        Assert.Null(await service.UpdateAsync(Guid.NewGuid(),
            new UpdateResourceRequest { Name = "valid", Type = "valid" }, default));
        Assert.False(await service.DeleteAsync(Guid.NewGuid(), default));
        Assert.Equal(0, repository.Saves);
    }

    [Fact]
    public async Task Delete_removes_the_found_resource_and_commits_once()
    {
        var repository = new MemoryResourceRepository();
        var entity = new ResourceEntity { Id = Guid.NewGuid(), Name = "Resource", Type = "generic" };
        repository.Resources.Add(entity);
        using var cancellation = new CancellationTokenSource();

        Assert.True(await new ResourceService(repository, new MemoryDesignRepository()).DeleteAsync(entity.Id, cancellation.Token));

        Assert.Empty(repository.Resources);
        Assert.Equal(1, repository.Saves);
        Assert.Equal(cancellation.Token, repository.LastToken);
    }

    [Fact]
    public async Task Reads_return_response_snapshots_without_persisting_and_forward_cancellation()
    {
        var repository = new MemoryResourceRepository();
        var entity = new ResourceEntity { Id = Guid.NewGuid(), Name = "Before", Type = "generic" };
        repository.Resources.Add(entity);
        var service = new ResourceService(repository, new MemoryDesignRepository());
        using var cancellation = new CancellationTokenSource();

        var found = await service.GetByIdAsync(entity.Id, cancellation.Token);
        var listed = Assert.Single(await service.ListAsync(cancellation.Token));
        Assert.Null(await service.GetByIdAsync(Guid.NewGuid(), cancellation.Token));
        entity.Name = "Changed later";

        Assert.NotNull(found);
        Assert.Equal("Before", found.Name);
        Assert.Equal("Before", listed.Name);
        Assert.Equal(0, repository.Saves);
        Assert.Equal(cancellation.Token, repository.LastToken);
    }

    [Fact]
    public async Task Cancellation_is_propagated_to_persistence()
    {
        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();
        var repository = new MemoryResourceRepository();
        var service = new ResourceService(repository, new MemoryDesignRepository());

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => service.CreateAsync(
            new CreateResourceRequest { Name = "valid", Type = "valid" }, cancellation.Token));

        Assert.Equal(0, repository.Saves);
    }

    [Fact]
    public async Task Explicit_ownership_is_required_to_exist_and_omitted_updates_preserve_it()
    {
        var repository = new MemoryResourceRepository();
        var designs = new MemoryDesignRepository();
        var first = new DesignEntity { Id = Guid.NewGuid(), Name = "First" };
        var second = new DesignEntity { Id = Guid.NewGuid(), Name = "Second" };
        designs.Designs.AddRange([first, second]);
        var service = new ResourceService(repository, designs);
        var created = await service.CreateAsync(new CreateResourceRequest
        { Name = "Resource", Type = "generic", DesignId = first.Id }, default);
        var entity = Assert.Single(repository.Resources);
        Assert.Equal(first.Id, entity.DesignId);
        Assert.Equal(0, designs.LegacyEnsures);

        await service.UpdateAsync(created.Id, new UpdateResourceRequest { Name = "Moved", Type = "generic" }, default);
        Assert.Equal(first.Id, entity.DesignId);
        await service.UpdateAsync(created.Id, new UpdateResourceRequest
        { Name = "Moved", Type = "generic", DesignId = second.Id }, default);
        Assert.Equal(second.Id, entity.DesignId);
        Assert.Empty(await service.ListByDesignIdAsync(first.Id, default));
        Assert.Equal(second.Id, Assert.Single(await service.ListByDesignIdAsync(second.Id, default)).DesignId);
    }

    [Fact]
    public async Task Missing_owners_are_rejected_before_mutation_or_save()
    {
        var repository = new MemoryResourceRepository();
        var designs = new MemoryDesignRepository();
        var owner = new DesignEntity { Id = Guid.NewGuid(), Name = "Owner" };
        designs.Designs.Add(owner);
        var entity = new ResourceEntity { Id = Guid.NewGuid(), DesignId = owner.Id, Name = "Original", Type = "generic" };
        repository.Resources.Add(entity);
        var service = new ResourceService(repository, designs);
        var missing = Guid.NewGuid();
        await Assert.ThrowsAsync<DesignNotFoundException>(() => service.CreateAsync(new CreateResourceRequest
        { Name = "New", Type = "generic", DesignId = missing }, default));
        await Assert.ThrowsAsync<DesignNotFoundException>(() => service.UpdateAsync(entity.Id, new UpdateResourceRequest
        { Name = "Changed", Type = "generic", DesignId = missing }, default));
        await Assert.ThrowsAsync<DesignNotFoundException>(() => service.ListByDesignIdAsync(missing, default));
        Assert.Equal("Original", entity.Name);
        Assert.Equal(owner.Id, entity.DesignId);
        Assert.Single(repository.Resources);
        Assert.Equal(0, repository.Saves);
        Assert.Equal(0, designs.LegacyEnsures);
    }

    private sealed class MemoryResourceRepository : IResourceRepository
    {
        public List<ResourceEntity> Resources { get; } = [];
        public int Lookups { get; private set; }
        public int Saves { get; private set; }
        public CancellationToken LastToken { get; private set; }

        public Task<IReadOnlyList<ResourceEntity>> ListByDesignIdAsync(Guid designId, CancellationToken ct)
        {
            ct.ThrowIfCancellationRequested();
            LastToken = ct;
            return Task.FromResult<IReadOnlyList<ResourceEntity>>(
                Resources.Where(resource => resource.DesignId == designId).ToArray());
        }

        public Task<IReadOnlyList<ResourceEntity>> ListAsync(CancellationToken ct)
        {
            ct.ThrowIfCancellationRequested();
            LastToken = ct;
            return Task.FromResult<IReadOnlyList<ResourceEntity>>(
                Resources.OrderByDescending(resource => resource.CreatedAtUtc).ToArray());
        }

        public Task<ResourceEntity?> GetByIdAsync(Guid id, CancellationToken ct)
        {
            ct.ThrowIfCancellationRequested();
            LastToken = ct;
            Lookups++;
            return Task.FromResult(Resources.FirstOrDefault(resource => resource.Id == id));
        }

        public void Add(ResourceEntity resource) => Resources.Add(resource);
        public void Remove(ResourceEntity resource) => Resources.Remove(resource);

        public Task SaveChangesAsync(CancellationToken ct)
        {
            ct.ThrowIfCancellationRequested();
            LastToken = ct;
            Saves++;
            return Task.CompletedTask;
        }
    }
}
