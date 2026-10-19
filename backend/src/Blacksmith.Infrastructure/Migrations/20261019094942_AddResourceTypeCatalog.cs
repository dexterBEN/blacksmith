using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

#pragma warning disable CA1814 // Prefer jagged arrays over multidimensional

namespace Blacksmith.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddResourceTypeCatalog : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<Guid>(
                name: "resource_type_id",
                table: "resources",
                type: "uuid",
                nullable: true);

            migrationBuilder.CreateTable(
                name: "resource_types",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Code = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    DisplayName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    Category = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_resource_types", x => x.Id);
                    table.UniqueConstraint("AK_resource_types_Code", x => x.Code);
                });

            migrationBuilder.InsertData(
                table: "resource_types",
                columns: new[] { "Id", "Category", "Code", "DisplayName" },
                values: new object[,]
                {
                    { new Guid("10000000-0000-0000-0000-000000000001"), "Compute", "virtual-machine", "Virtual Machine" },
                    { new Guid("10000000-0000-0000-0000-000000000002"), "Storage", "storage", "Storage" },
                    { new Guid("10000000-0000-0000-0000-000000000003"), "Data", "database", "Database" },
                    { new Guid("10000000-0000-0000-0000-000000000004"), "Networking", "network", "Network" },
                    { new Guid("10000000-0000-0000-0000-000000000005"), "Networking", "gateway", "Gateway" },
                    { new Guid("10000000-0000-0000-0000-000000000006"), "Networking", "load-balancer", "Load Balancer" }
                });

            // Preserve historical strings verbatim. Unknown/provider-specific values stay unclassified.
            migrationBuilder.Sql("""
                UPDATE resources AS resource
                SET resource_type_id = catalog."Id"
                FROM resource_types AS catalog
                WHERE resource."Type" = catalog."Code";
                """);

            migrationBuilder.CreateIndex(
                name: "IX_resources_resource_type_id",
                table: "resources",
                column: "resource_type_id");

            migrationBuilder.AddForeignKey(
                name: "FK_resources_resource_types_resource_type_id",
                table: "resources",
                column: "resource_type_id",
                principalTable: "resource_types",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_resources_resource_types_resource_type_id",
                table: "resources");

            migrationBuilder.DropTable(
                name: "resource_types");

            migrationBuilder.DropIndex(
                name: "IX_resources_resource_type_id",
                table: "resources");

            migrationBuilder.DropColumn(
                name: "resource_type_id",
                table: "resources");
        }
    }
}
