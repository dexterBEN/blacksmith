using Blacksmith.Domain.Entities;
using Microsoft.EntityFrameworkCore;

namespace Blacksmith.Infrastructure.Persistence;

public sealed class BlacksmithDbContext : DbContext
{
    public const string ResourceDesignForeignKey = "FK_resources_designs_design_id";
    public const string ResourceTypeForeignKey = "FK_resources_resource_types_resource_type_id";
    public BlacksmithDbContext(DbContextOptions<BlacksmithDbContext> options) : base(options) { }

    public DbSet<ResourceEntity> Resources => Set<ResourceEntity>();
    public DbSet<DesignEntity> Designs => Set<DesignEntity>();
    public DbSet<ResourceTypeEntity> ResourceTypes => Set<ResourceTypeEntity>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<ResourceTypeEntity>(entity =>
        {
            entity.ToTable("resource_types");
            entity.HasKey(x => x.Id);
            entity.Property(x => x.Code).IsRequired().HasMaxLength(100);
            entity.HasAlternateKey(x => x.Code).HasName("AK_resource_types_Code");
            entity.Property(x => x.DisplayName).IsRequired().HasMaxLength(200);
            entity.Property(x => x.Category).IsRequired().HasMaxLength(100);
            entity.HasData(
                new ResourceTypeEntity { Id = new Guid("10000000-0000-0000-0000-000000000001"), Code = "virtual-machine", DisplayName = "Virtual Machine", Category = "Compute" },
                new ResourceTypeEntity { Id = new Guid("10000000-0000-0000-0000-000000000002"), Code = "storage", DisplayName = "Storage", Category = "Storage" },
                new ResourceTypeEntity { Id = new Guid("10000000-0000-0000-0000-000000000003"), Code = "database", DisplayName = "Database", Category = "Data" },
                new ResourceTypeEntity { Id = new Guid("10000000-0000-0000-0000-000000000004"), Code = "network", DisplayName = "Network", Category = "Networking" },
                new ResourceTypeEntity { Id = new Guid("10000000-0000-0000-0000-000000000005"), Code = "gateway", DisplayName = "Gateway", Category = "Networking" },
                new ResourceTypeEntity { Id = new Guid("10000000-0000-0000-0000-000000000006"), Code = "load-balancer", DisplayName = "Load Balancer", Category = "Networking" });
        });

        modelBuilder.Entity<DesignEntity>(entity =>
        {
            entity.ToTable("designs");
            entity.HasKey(x => x.Id);
            entity.Property(x => x.Name).IsRequired().HasMaxLength(200);
            entity.Property(x => x.Description);
            entity.Property(x => x.CreatedAtUtc)
                .HasColumnName("created_at_utc").IsRequired().HasDefaultValueSql("NOW()");
            entity.Property(x => x.UpdatedAtUtc)
                .HasColumnName("updated_at_utc").IsRequired().HasDefaultValueSql("NOW()");
        });

        modelBuilder.Entity<ResourceEntity>(entity =>
        {
            entity.ToTable("resources");
            entity.HasKey(x => x.Id);
            entity.Property(x => x.DesignId).HasColumnName("design_id").IsRequired();
            entity.Property(x => x.ResourceTypeId).HasColumnName("resource_type_id");
            entity.HasIndex(x => x.ResourceTypeId).HasDatabaseName("IX_resources_resource_type_id");
            entity.HasOne(x => x.ResourceType).WithMany(x => x.Resources).HasForeignKey(x => x.ResourceTypeId)
                .OnDelete(DeleteBehavior.Restrict).HasConstraintName(ResourceTypeForeignKey);
            entity.HasIndex(x => x.DesignId).HasDatabaseName("IX_resources_design_id");
            entity.HasOne(x => x.Design).WithMany(x => x.Resources).HasForeignKey(x => x.DesignId)
                .OnDelete(DeleteBehavior.Restrict).HasConstraintName(ResourceDesignForeignKey);
            entity.Property(x => x.Name).IsRequired().HasMaxLength(200);
            entity.Property(x => x.Type).IsRequired().HasMaxLength(100);
            entity.Property(x => x.X).HasColumnName("x").IsRequired();
            entity.Property(x => x.Y).HasColumnName("y").IsRequired();
            entity.Property(x => x.CreatedAtUtc)
                .HasColumnName("created_at_utc").IsRequired().HasDefaultValueSql("NOW()");
        });
    }
}
