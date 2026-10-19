using Blacksmith.Domain.Entities;
using Microsoft.EntityFrameworkCore;

namespace Blacksmith.Infrastructure.Persistence;

public sealed class BlacksmithDbContext : DbContext
{
    public const string ResourceDesignForeignKey = "FK_resources_designs_design_id";
    public BlacksmithDbContext(DbContextOptions<BlacksmithDbContext> options) : base(options) { }

    public DbSet<ResourceEntity> Resources => Set<ResourceEntity>();
    public DbSet<DesignEntity> Designs => Set<DesignEntity>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
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
