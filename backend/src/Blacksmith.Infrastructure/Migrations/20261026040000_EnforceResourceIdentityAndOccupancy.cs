using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Blacksmith.Infrastructure.Migrations;

public partial class EnforceResourceIdentityAndOccupancy : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        // EF executes this preflight and the schema changes in the same transaction.
        // Block writers so a clean preflight cannot race another legacy insert.
        migrationBuilder.Sql("""
            LOCK TABLE resources IN SHARE ROW EXCLUSIVE MODE;
            DO $$
            BEGIN
                IF EXISTS (SELECT 1 FROM resources GROUP BY design_id, x, y HAVING count(*) > 1) THEN
                    RAISE EXCEPTION USING ERRCODE = '23505',
                        MESSAGE = 'Duplicate Resource tile occupancy. Migration stopped without changing data.',
                        HINT = 'Review SELECT design_id,x,y,count(*) FROM resources GROUP BY design_id,x,y HAVING count(*)>1; resolve conflicts explicitly before retrying.';
                END IF;
            END $$;
            """);
        migrationBuilder.AddColumn<long>(name: "revision", table: "resources", type: "bigint", nullable: false, defaultValue: 1L);
        migrationBuilder.CreateIndex(name: "UX_resources_design_id_x_y", table: "resources", columns: new[] { "design_id", "x", "y" }, unique: true);
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropIndex(name: "UX_resources_design_id_x_y", table: "resources");
        migrationBuilder.DropColumn(name: "revision", table: "resources");
    }
}
