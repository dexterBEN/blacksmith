using CloudServices.Api.Domain;
using Microsoft.EntityFrameworkCore;

namespace CloudServices.Api.Data;

public sealed class BlacksmithDbContext : DbContext
{
    public BlacksmithDbContext(DbContextOptions<BlacksmithDbContext> options)
        : base(options) { }

    public DbSet<ResourceEntity> Resources => Set<ResourceEntity>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<ResourceEntity>(entity =>
        {
            entity.ToTable("resources");
            entity.HasKey(x => x.Id);

            entity.Property(x => x.Name)
                  .IsRequired()
                  .HasMaxLength(200);

            entity.Property(x => x.Type)
                  .IsRequired()
                  .HasMaxLength(100);

            entity.Property(x => x.X)
                  .HasColumnName("x")
                  .IsRequired();

            entity.Property(x => x.Y)
                  .HasColumnName("y")
                  .IsRequired();

            entity.Property(x => x.CreatedAtUtc)
                  .HasColumnName("created_at_utc")
                  .IsRequired()
                  .HasDefaultValueSql("NOW()");
        });
    }
}