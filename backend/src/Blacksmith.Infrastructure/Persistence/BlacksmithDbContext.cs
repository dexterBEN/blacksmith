using Blacksmith.Domain.Entities;
using Microsoft.EntityFrameworkCore;

namespace Blacksmith.Infrastructure.Persistence;

public sealed class BlacksmithDbContext : DbContext
{
    public const string ResourceDesignForeignKey = "FK_resources_designs_design_id";
    public const string ResourceTypeForeignKey = "FK_resources_resource_types_resource_type_id";
    public const string ResourceTileIndex = "UX_resources_design_id_x_y";
    public BlacksmithDbContext(DbContextOptions<BlacksmithDbContext> options) : base(options) { }

    public DbSet<ResourceEntity> Resources => Set<ResourceEntity>();
    public DbSet<DesignEntity> Designs => Set<DesignEntity>();
    public DbSet<ResourceTypeEntity> ResourceTypes => Set<ResourceTypeEntity>();
    public DbSet<ResourceConfiguration> ResourceConfigurations => Set<ResourceConfiguration>();
    public DbSet<StorageDeployment> StorageDeployments => Set<StorageDeployment>();
    public DbSet<StorageDeploymentAttempt> StorageDeploymentAttempts => Set<StorageDeploymentAttempt>();

    public DbSet<StorageDeletion> StorageDeletions => Set<StorageDeletion>();
    public DbSet<StorageDeletionAttempt> StorageDeletionAttempts => Set<StorageDeletionAttempt>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<StorageDeletion>(entity =>
        {
            entity.ToTable("storage_deletions", table => table.HasCheckConstraint(
                "CK_storage_deletions_status", "\"Status\" IN ('pending','succeeded','failed','unknown')"));
            entity.HasKey(x => x.ResourceId);
            entity.Property(x => x.ResourceId).ValueGeneratedNever();
            entity.HasIndex(x => x.Id).IsUnique();
            entity.Property(x => x.ProjectId).HasMaxLength(30);
            entity.Property(x => x.BucketName).HasMaxLength(63);
            entity.Property(x => x.Location).HasMaxLength(40);
            entity.Property(x => x.OwnershipMarker).HasMaxLength(32);
            entity.Property(x => x.Status).HasMaxLength(16);
            entity.Property(x => x.Code).HasMaxLength(60);
            entity.Property(x => x.Version).IsConcurrencyToken();
        });
        modelBuilder.Entity<StorageDeletionAttempt>(entity =>
        {
            entity.ToTable("storage_deletion_attempts");
            entity.HasKey(x => x.Id);
            entity.Property(x => x.Id).ValueGeneratedNever();
            entity.HasOne(x => x.Deletion).WithMany().HasForeignKey(x => x.ResourceId).OnDelete(DeleteBehavior.Restrict);
        });
        modelBuilder.Entity<StorageDeployment>(entity =>
        {
            entity.ToTable("storage_deployments", table => {
                table.HasCheckConstraint("CK_storage_deployments_revision", "resource_revision > 0");
                table.HasCheckConstraint("CK_storage_deployments_status", "status IN ('pending','succeeded','failed','unknown')");
            });
            entity.HasKey(x => x.Id);
            entity.Property(x => x.Id).HasColumnName("id").ValueGeneratedNever();
            entity.Property(x => x.ResourceId).HasColumnName("resource_id");
            entity.Property(x => x.DesignId).HasColumnName("design_id");
            entity.Property(x => x.ResourceRevision).HasColumnName("resource_revision");
            entity.HasIndex(x => new { x.ResourceId, x.ResourceRevision }).IsUnique();
            entity.Property(x => x.RequestHash).HasMaxLength(64).IsRequired();
            entity.Property(x => x.ConfigurationHash).HasMaxLength(64).IsRequired();
            entity.Property(x => x.Configuration).HasColumnType("jsonb").IsRequired();
            entity.Property(x => x.OwnershipMarker).HasMaxLength(32).IsRequired();
            entity.Property(x => x.ProjectId).HasMaxLength(30).IsRequired();
            entity.Property(x => x.BucketName).HasMaxLength(63).IsRequired();
            entity.Property(x => x.Location).HasMaxLength(40).IsRequired();
            entity.Property(x => x.Status).HasColumnName("status").HasMaxLength(16).IsRequired();
            entity.Property(x => x.Code).HasMaxLength(60).IsRequired();
            entity.Property(x => x.Version).IsConcurrencyToken();
            entity.HasOne(x => x.Resource).WithMany(x => x.Deployments).HasForeignKey(x => x.ResourceId)
                .OnDelete(DeleteBehavior.Restrict).HasConstraintName("FK_storage_deployments_resources_resource_id");
        });
        modelBuilder.Entity<StorageDeploymentAttempt>(entity =>
        {
            entity.ToTable("storage_deployment_attempts");
            entity.HasKey(x => x.Id);
            entity.Property(x => x.Id).ValueGeneratedNever();
            entity.HasOne(x => x.Deployment).WithMany(x => x.Attempts).HasForeignKey(x => x.DeploymentId)
                .OnDelete(DeleteBehavior.Restrict);
        });

        modelBuilder.Entity<ResourceConfiguration>(entity =>
        {
            entity.ToTable("resource_configurations", table =>
                table.HasCheckConstraint("CK_resource_configurations_schema_version_positive", "schema_version > 0"));
            entity.HasKey(x => x.ResourceId);
            entity.Property(x => x.ResourceId).HasColumnName("resource_id").ValueGeneratedNever();
            entity.Property(x => x.SchemaVersion).HasColumnName("schema_version").IsRequired();
            entity.Property(x => x.Configuration).HasColumnName("configuration").HasColumnType("jsonb").IsRequired();
            entity.HasOne(x => x.Resource).WithOne(x => x.Configuration)
                .HasForeignKey<ResourceConfiguration>(x => x.ResourceId)
                .OnDelete(DeleteBehavior.Cascade);
        });

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
            entity.Property(x => x.Revision).HasColumnName("revision").HasDefaultValue(1L).IsConcurrencyToken();
            entity.HasIndex(x => new { x.DesignId, x.X, x.Y }).IsUnique().HasDatabaseName(ResourceTileIndex);
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
