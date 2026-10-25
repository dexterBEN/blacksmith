using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Blacksmith.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddResourceConfigurations : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "resource_configurations",
                columns: table => new
                {
                    resource_id = table.Column<Guid>(type: "uuid", nullable: false),
                    schema_version = table.Column<int>(type: "integer", nullable: false),
                    configuration = table.Column<string>(type: "jsonb", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_resource_configurations", x => x.resource_id);
                    table.CheckConstraint("CK_resource_configurations_schema_version_positive", "schema_version > 0");
                    table.ForeignKey(
                        name: "FK_resource_configurations_resources_resource_id",
                        column: x => x.resource_id,
                        principalTable: "resources",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "resource_configurations");
        }
    }
}
