using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Blacksmith.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddStorageDeployments : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "storage_deployments",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    resource_id = table.Column<Guid>(type: "uuid", nullable: false),
                    design_id = table.Column<Guid>(type: "uuid", nullable: false),
                    resource_revision = table.Column<long>(type: "bigint", nullable: false),
                    RequestHash = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    ConfigurationHash = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    Configuration = table.Column<string>(type: "jsonb", nullable: false),
                    OwnershipMarker = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    ProjectId = table.Column<string>(type: "character varying(30)", maxLength: 30, nullable: false),
                    BucketName = table.Column<string>(type: "character varying(63)", maxLength: 63, nullable: false),
                    Location = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    status = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    Code = table.Column<string>(type: "character varying(60)", maxLength: 60, nullable: false),
                    CurrentAttemptId = table.Column<Guid>(type: "uuid", nullable: true),
                    LeaseUntilUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    CreatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    Version = table.Column<long>(type: "bigint", nullable: false),
                    RemoteProjectNumber = table.Column<string>(type: "text", nullable: true),
                    RemoteBucketId = table.Column<string>(type: "text", nullable: true),
                    RemoteMetageneration = table.Column<string>(type: "text", nullable: true),
                    OwnershipVerified = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_storage_deployments", x => x.id);
                    table.CheckConstraint("CK_storage_deployments_revision", "resource_revision > 0");
                    table.CheckConstraint("CK_storage_deployments_status", "status IN ('pending','succeeded','failed','unknown')");
                    table.ForeignKey(
                        name: "FK_storage_deployments_resources_resource_id",
                        column: x => x.resource_id,
                        principalTable: "resources",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "storage_deployment_attempts",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    DeploymentId = table.Column<Guid>(type: "uuid", nullable: false),
                    CreatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_storage_deployment_attempts", x => x.Id);
                    table.ForeignKey(
                        name: "FK_storage_deployment_attempts_storage_deployments_DeploymentId",
                        column: x => x.DeploymentId,
                        principalTable: "storage_deployments",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "IX_storage_deployment_attempts_DeploymentId",
                table: "storage_deployment_attempts",
                column: "DeploymentId");

            migrationBuilder.CreateIndex(
                name: "IX_storage_deployments_resource_id_resource_revision",
                table: "storage_deployments",
                columns: new[] { "resource_id", "resource_revision" },
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "storage_deployment_attempts");

            migrationBuilder.DropTable(
                name: "storage_deployments");
        }
    }
}
