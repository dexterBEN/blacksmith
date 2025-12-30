using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace CloudServices.Api.Migrations
{
    /// <inheritdoc />
    public partial class AddResourcesTable : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.RenameColumn(
                name: "Y",
                table: "resources",
                newName: "y");

            migrationBuilder.RenameColumn(
                name: "X",
                table: "resources",
                newName: "x");

            migrationBuilder.RenameColumn(
                name: "CreatedAtUtc",
                table: "resources",
                newName: "created_at_utc");

            migrationBuilder.AlterColumn<DateTime>(
                name: "created_at_utc",
                table: "resources",
                type: "timestamp with time zone",
                nullable: false,
                defaultValueSql: "NOW()",
                oldClrType: typeof(DateTime),
                oldType: "timestamp with time zone");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.RenameColumn(
                name: "y",
                table: "resources",
                newName: "Y");

            migrationBuilder.RenameColumn(
                name: "x",
                table: "resources",
                newName: "X");

            migrationBuilder.RenameColumn(
                name: "created_at_utc",
                table: "resources",
                newName: "CreatedAtUtc");

            migrationBuilder.AlterColumn<DateTime>(
                name: "CreatedAtUtc",
                table: "resources",
                type: "timestamp with time zone",
                nullable: false,
                oldClrType: typeof(DateTime),
                oldType: "timestamp with time zone",
                oldDefaultValueSql: "NOW()");
        }
    }
}
