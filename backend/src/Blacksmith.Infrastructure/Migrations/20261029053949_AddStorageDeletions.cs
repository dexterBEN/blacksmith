using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Blacksmith.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddStorageDeletions : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "storage_deletions",
                columns: table => new
                {
                    ResourceId = table.Column<Guid>(type: "uuid", nullable: false),
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    DesignId = table.Column<Guid>(type: "uuid", nullable: false),
                    ResourceRevision = table.Column<long>(type: "bigint", nullable: false),
                    ProjectId = table.Column<string>(type: "character varying(30)", maxLength: 30, nullable: false),
                    BucketName = table.Column<string>(type: "character varying(63)", maxLength: 63, nullable: false),
                    Location = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    OwnershipMarker = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    Status = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    Code = table.Column<string>(type: "character varying(60)", maxLength: 60, nullable: false),
                    CurrentAttemptId = table.Column<Guid>(type: "uuid", nullable: false),
                    LeaseUntilUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    UpdatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    Version = table.Column<long>(type: "bigint", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_storage_deletions", x => x.ResourceId);
                    table.CheckConstraint("CK_storage_deletions_status", "\"Status\" IN ('pending','succeeded','failed','unknown')");
                });

            migrationBuilder.CreateTable(
                name: "storage_deletion_attempts",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    ResourceId = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_storage_deletion_attempts", x => x.Id);
                    table.ForeignKey(
                        name: "FK_storage_deletion_attempts_storage_deletions_ResourceId",
                        column: x => x.ResourceId,
                        principalTable: "storage_deletions",
                        principalColumn: "ResourceId",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "IX_storage_deletion_attempts_ResourceId",
                table: "storage_deletion_attempts",
                column: "ResourceId");

            migrationBuilder.CreateIndex(
                name: "IX_storage_deletions_Id",
                table: "storage_deletions",
                column: "Id",
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "storage_deletion_attempts");

            migrationBuilder.DropTable(
                name: "storage_deletions");
        }
    }
}
