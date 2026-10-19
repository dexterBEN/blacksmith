using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Blacksmith.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddDesignOwnership : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "designs",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Name = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    Description = table.Column<string>(type: "text", nullable: true),
                    created_at_utc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false, defaultValueSql: "NOW()"),
                    updated_at_utc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false, defaultValueSql: "NOW()")
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_designs", x => x.Id);
                });

            migrationBuilder.AddColumn<Guid>(
                name: "design_id",
                table: "resources",
                type: "uuid",
                nullable: true);

            // Keep historical migration values literal: changing runtime defaults must not change old migrations.
            migrationBuilder.Sql("""
                INSERT INTO designs ("Id", "Name", "Description", created_at_utc, updated_at_utc)
                VALUES ('00000000-0000-0000-0000-000000000001'::uuid, 'Legacy design',
                    'Resources migrated from the single-canvas application.', NOW(), NOW());

                UPDATE resources
                SET design_id = '00000000-0000-0000-0000-000000000001'::uuid
                WHERE design_id IS NULL;
                """);

            migrationBuilder.AlterColumn<Guid>(
                name: "design_id",
                table: "resources",
                type: "uuid",
                nullable: false,
                oldClrType: typeof(Guid),
                oldType: "uuid",
                oldNullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_resources_design_id",
                table: "resources",
                column: "design_id");

            migrationBuilder.AddForeignKey(
                name: "FK_resources_designs_design_id",
                table: "resources",
                column: "design_id",
                principalTable: "designs",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_resources_designs_design_id",
                table: "resources");

            migrationBuilder.DropIndex(
                name: "IX_resources_design_id",
                table: "resources");

            migrationBuilder.DropColumn(
                name: "design_id",
                table: "resources");

            // Resource data survives, but design metadata and ownership cannot survive this downgrade.
            migrationBuilder.DropTable(
                name: "designs");
        }
    }
}
