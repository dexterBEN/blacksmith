# Issue #9 — Generic Resource Type Catalog

Implements [Issue #9](https://github.com/dexterBEN/blacksmith/issues/9) on branch `issue_9`, based on updated `master` at `4b535fd`.

## Result

The backend now exposes the six generic resource types through read-only endpoints, classifies exact legacy-code matches, and validates explicit catalog references without changing existing resource response shapes. PostgreSQL enforces code uniqueness and restrictive references. Classification remains independent of provisioning.

The nine-project solution builds successfully inside the backend devcontainer. **All 91 tests pass: 31 application tests, 49 HTTP/model integration tests and 11 PostgreSQL tests, with zero failures and zero skipped tests.**

## Analysis and implementation plan

The existing backend separates Domain, Application, Infrastructure and API. Resources already belong to a design, while `Resource.Type` is a required free-form string. Existing resource responses have six fields, and the response listing resources by design has seven; both contracts must remain unchanged.

The inspected Godot source calls the cloud ping and bucket creation routes, not the `/resources` CRUD endpoints. Its `ResourceType` enum contains `storageBucket`, `database`, `vm`, `loadBalancer` and `cache`, but is not serialized into API resource type strings. Existing backend tests use `gcp.storage.bucket`, `generic`, `custom.type` and arbitrary strings. These are examples from source code, not a claimed inventory of development database data. No development database inspection or migration is required.

Planned implementation:

1. Add a framework-independent `ResourceTypeEntity` with stable catalog codes; add its read-only repository, service, DTO and controller.
2. Add nullable `Resource.ResourceTypeId` and a restrictive FK for the compatibility phase. Seed the six generic catalog entries with fixed UUIDs. Backfill only exact catalog-code matches, preserving every original field. Unknown, provider-specific, differently cased and whitespace-padded historical strings remain unclassified with a null FK.
3. Keep legacy `Type` required and preserve response shapes. Accept an optional explicit `resourceTypeId`, validate it and reject contradictory known catalog codes. Preserve an explicit classification when a legacy update leaves `Type` unchanged; resolve a changed legacy string again instead of retaining an unrelated classification.
4. Extend application, HTTP/SQLite and isolated PostgreSQL tests. Execute restore/build/tests inside the backend devcontainer. Update architecture documentation, commit all required files, and validate the committed source from a separate clean export.

Generic classification does not select a GCP service or invoke provisioning. In particular, neither a migration nor a resource write automatically maps `gcp.storage.bucket` to `storage`.

## Working tree preservation

Before switching branches, two pre-existing documentation edits from Issue #7 were saved and byte/hash verified in `/home/dexter/Documents/blacksmith-recovery/2026-10-19-before-issue-9`. The backup contains both files, their patch and a SHA-256 manifest. The separate Issue #4 recovery backup was not modified. No Git stash was created or removed.

The requested pull was executed as `git pull --rebase origin master`, followed by `git switch -c issue_9`. The update was a fast-forward. The architecture page is now updated in English for this issue. The README includes the documentation link with wording extended to cover the catalog; both earlier documents remain recoverable in the backup.

## Changes by layer and affected files

| Area | Files and behavior |
| --- | --- |
| Domain | Adds `Entities/ResourceTypeEntity.cs`; extends `ResourceEntity.cs` with nullable `ResourceTypeId` and navigation |
| Application contracts | Adds `ResourceTypeResponse.cs`, `IResourceTypeRepository.cs`, `IResourceTypeService.cs`, and `ResourceTypeNotFoundException.cs`; adds optional `ResourceTypeId` to create/update request DTOs |
| Application services | Adds `ResourceTypeService.cs`; extends `ResourceService.cs` with exact code resolution and explicit-reference validation |
| Infrastructure | Adds `EfResourceTypeRepository.cs`; updates DbContext mappings/seeds, dependency injection and the resource repository's targeted FK error handling |
| Migrations | Adds `20261019094942_AddResourceTypeCatalog.cs` and its Designer, and updates `BlacksmithDbContextModelSnapshot.cs` |
| API | Adds `ResourceTypesController.cs`, registers the new service in `Program.cs`, and handles missing catalog references in `ResourcesController.cs` |
| Application tests | Adds `MemoryResourceTypeRepository.cs` and `ResourceTypeServiceTests.cs`; extends `ResourceServiceTests.cs` |
| HTTP/model tests | Adds `ResourceTypeApiTests.cs`; extends `DatabaseContractTests.cs` for the new model/migration |
| PostgreSQL tests | Adds `ResourceTypeCatalogTests.cs`; updates the expected migration count in existing `MigrationTests.cs` |
| Documentation | Updates `docs/backend/current-architecture.md` in English, adds its README link, and includes this report |

No `.csproj` or `.sln` changes are needed: the existing nine projects, including the PostgreSQL test project, are already tracked on updated master. Source files are included through the existing SDK project conventions. No dependency or framework was added to Domain or Application. The GCP implementation, cloud contract, frontend, development container configuration and Docker Compose files are unchanged.

## Catalog and API

| Stable UUID | Code | Display name | Category |
| --- | --- | --- | --- |
| `10000000-0000-0000-0000-000000000001` | `virtual-machine` | Virtual Machine | Compute |
| `10000000-0000-0000-0000-000000000002` | `storage` | Storage | Storage |
| `10000000-0000-0000-0000-000000000003` | `database` | Database | Data |
| `10000000-0000-0000-0000-000000000004` | `network` | Network | Networking |
| `10000000-0000-0000-0000-000000000005` | `gateway` | Gateway | Networking |
| `10000000-0000-0000-0000-000000000006` | `load-balancer` | Load Balancer | Networking |

`GET /resource-types` returns `200` and entries sorted by code. `GET /resource-types/{id:guid}` returns `200` or `404`. DTOs contain exactly `id`, `code`, `displayName` and `category`. No catalog mutation endpoint is introduced; POST/PUT/DELETE to the matching read-only routes return `405`.

The flow remains Controller → Service → Repository. Repositories perform SQL filtering and use `AsNoTracking` for catalog reads. Cancellation propagates through the service and repository. Codes have the actual SQL unique constraint `AK_resource_types_Code`, rather than uniqueness being enforced only by application code.

The architecture page contains the updated layer diagram, UML and PostgreSQL ERD. It explicitly shows optional classification during this transition and required design ownership.

## Compatibility decisions

`Type` remains required. The existing validation order, trimming, coordinates and resource identity/creation-time behavior are retained. Existing `/resources` responses still contain exactly `id`, `name`, `x`, `y`, `type`, `createdAtUtc`. Lists by design retain their previous fields, including `designId`, without adding a classification field.

| Request | Classification behavior |
| --- | --- |
| Create without `resourceTypeId` | Resolve the trimmed `Type` only when it exactly matches an existing catalog code |
| Create/update with explicit `resourceTypeId` | Verify the catalog entry exists; otherwise `404` with `Resource type not found.` |
| Explicit ID plus a different known generic `Type` code | Reject with `400`: `Type and resourceTypeId refer to different catalog entries` |
| Explicit ID plus unknown/provider-specific legacy text | Accept the caller's explicit classification while preserving that legacy text |
| Update omitting the ID with unchanged `Type` | Preserve the existing explicit classification |
| Update omitting the ID with changed `Type` | Resolve the replacement text; clear the previous classification if the replacement is unknown |
| Explicit `null` ID | Same behavior as omission; not a request to clear classification |

For example, `type: "gcp.storage.bucket"` alone remains valid and unclassified. Supplying the Storage UUID explicitly classifies that resource without altering its legacy type or invoking Google Cloud. The generic code `storage` automatically resolves to Storage, but `Storage`, `vm`, `generic` and provider service names are not guessed aliases.

Validation occurs before mutating a resource or creating a legacy design as a side effect. Unknown explicit IDs do not silently fall back to inference. Existing name/type validation and missing resource behavior remain covered by retained tests.

## Migration and referential integrity

`20261019094942_AddResourceTypeCatalog` adds the nullable UUID column, creates `resource_types`, seeds six literal fixed entries, backfills exact matches, creates `IX_resources_resource_type_id`, and adds `FK_resources_resource_types_resource_type_id` with `ON DELETE RESTRICT`.

The backfill is deliberately narrow:

```sql
UPDATE resources AS resource
SET resource_type_id = catalog."Id"
FROM resource_types AS catalog
WHERE resource."Type" = catalog."Code";
```

It does not rewrite, trim or lowercase existing `Type` strings. Historical unknown strings, differently cased values, padded strings and provider-specific names retain their original values with a null FK. No catch-all category or invented legacy catalog entry is introduced. There is no database default for the new FK.

The first three migrations remain unchanged. The resources table is not recreated; IDs, names, types, positions, creation timestamps and design ownership are preserved. The generated idempotent SQL was inspected for ordering, the real unique constraint, the index and restrictive deletion. The Npgsql model matches the new snapshot with no pending changes.

Referenced types cannot be deleted in PostgreSQL. If an unreferenced type is deleted after application validation but before the resource write, the database rejects that write; Infrastructure translates only SQLSTATE `23503` for this exact FK into `ResourceTypeNotFoundException`, resulting in HTTP `404`. The test forces that interleaving using independent database connections. No orphan resource or cloud call results. Existing design concurrency protections remain intact, and unrelated database errors are not reclassified.

The API does not migrate at startup. No migration or destructive test was run against the development database. Schema rollout should follow SQL review, backup and coordination of writes; backfill/index creation/FK validation may lock the table. No large-volume performance claim is made.

### Rollback limitations

Downgrading only the new migration removes the type FK/index/column/catalog while preserving all original resource values and design ownership. It loses explicit catalog assignments, especially those associated with unknown/provider-specific legacy strings. Reapplying can reconstruct only exact generic-code matches; a backup is required to recover explicit assignments. Downgrading through the older design migration has its own additional ownership loss, documented separately.

## Validation and development environment

All .NET restore/build/test commands ran inside existing devcontainer `cb8b48194ed2`, with UID/GID `1000:1000`, using .NET SDK **8.0.426** and EF tooling **8.0.11**. Git operations ran on the VM against the shared repository; Git is not required inside the container for this build.

An initial NuGet invocation under numeric UID 1000 failed with a `NuGet-Migrations` mutex error. That UID had no local account in the image. A locked account/group was added only inside the running container, after which restore/build/tests succeeded without producing root-owned source files. The tracked devcontainer configuration was not changed. The first SDK invocation also printed a workload-verification notice; no workload update was performed, and the solution builds reported zero warnings/errors.

PostgreSQL **16.15** binaries for Debian 12 were downloaded from the official PostgreSQL repository, with package SHA-256 verification, and extracted under `/tmp/blacksmith-issue9/pg-root`. The missing `libxml2` dependency was also extracted under `/tmp`. Neither PostgreSQL nor that library was installed system-wide. These are temporary tooling files, not repository dependencies.

The existing PostgreSQL script started a fresh cluster accessible only through a private Unix socket inside the devcontainer and stopped it on exit. It did not use the running development PostgreSQL container or its data/volumes. Tests reused the existing isolated-database fixture, which creates a unique database per test and drops only that database. The fixture retains its existing `blacksmith_issue7_` naming prefix; uniqueness and isolation do not depend on the issue number.

| Check | Working tree result |
| --- | --- |
| Restore all nine projects | Passed |
| Release build | Passed, zero warnings/errors |
| `Blacksmith.Application.Tests` | 31 passed, zero failed/skipped |
| `Blacksmith.IntegrationTests` | 49 passed, zero failed/skipped |
| `Blacksmith.PostgreSql.Tests` | 11 passed, zero failed/skipped |
| Npgsql model vs snapshot | No pending changes |
| Historical migrations and out-of-scope components | Unchanged |
| Generated idempotent SQL | Reviewed |
| Whitespace/line endings | Checked, preserving existing CRLF conventions |

The 30 new test cases cover catalog reads/DTOs, cancellation, fixed IDs and metadata, read-only routes, legacy compatibility, explicit reference validation, contradictory input, classification preservation/re-resolution, migrations on empty/populated databases, unique/FK/RESTRICT behavior, downgrade/reapply, and a concurrent catalog deletion. All 61 pre-existing tests remain in the solution; fixtures and model expectations were updated without removing existing contract assertions.

The populated migration test includes every generic code and historical examples `gcp.storage.bucket`, `custom.type`, `Storage`, ` storage `, `vm` and an empty string accepted by the old SQL schema. It compares all seven original persisted values, including `DesignId`, before migration, after migration, after downgrade and after reapplication.

Working tree results are retained in three TRX files inside the devcontainer at `/tmp/blacksmith-issue9/results-working-tree`. The temporary cluster `/tmp/blacksmith-pg-tests.ga5sndFH` is stopped and its files/logs retained. Paths are local evidence, not portable project requirements.

### Reproduce

Inside a suitable .NET 8 / PostgreSQL 16 development environment, from the repository root:

```bash
dotnet restore backend/BlacksmithBackend.sln
dotnet build backend/BlacksmithBackend.sln --configuration Release --no-restore
PG_BINDIR=/usr/lib/postgresql/16/bin bash backend/scripts/test-postgresql.sh --no-build --no-restore
```

For this running devcontainer, `PG_BINDIR` was `/tmp/blacksmith-issue9/pg-root/usr/lib/postgresql/16/bin`; `LD_LIBRARY_PATH` included `/tmp/blacksmith-issue9/pg-root/usr/lib/x86_64-linux-gnu`. Private CLI/cache/temp directories were also selected under `/tmp/blacksmith-issue9`.

Without `BLACKSMITH_TEST_POSTGRES`, an ordinary `dotnet test` explicitly skips PostgreSQL cases. Such a run is not a complete database validation. All 11 PostgreSQL cases actually ran in the recorded execution.

### Committed-source verification

Implementation commit: **`5bc17b53233af2590e088630442c1607512bcb8b`** (`feat(backend): add generic resource type catalog`).

A clean archive generated solely from this commit contained 83 source/documentation files and all nine `.csproj` files, with no local `bin`, `obj`, ignored environment files or untracked source. Archive SHA-256: `199fcd1a45da08b25d5aa89e021895a96a5285ebead7463558a08e4f5e6896e8`.

The archive was extracted as UID/GID 1000 into `/tmp/blacksmith-issue9/committed-source` inside the devcontainer. Restore and a fresh Release build passed with zero warnings/errors. A second private PostgreSQL cluster then ran **all 91 tests successfully: 31 application, 49 integration, 11 PostgreSQL; zero failures and zero skipped tests**. The three TRX counters were also independently parsed and checked on the VM.

Committed-source results remain under `/tmp/blacksmith-issue9/results-committed` inside the container, with a copy at `/tmp/blacksmith-issue9-tools/results-committed` on the VM. The second cluster, `/tmp/blacksmith-pg-tests.3enbYZ7v`, was stopped and its files/logs retained. Both test runs left the development database untouched.

A subsequent documentation-only commit records these results. The backend source, project files and solution remain identical to the verified implementation commit. No push or shared-history rewrite was performed.

## Observations and remaining limitations

1. **Progressive classification is intentional.** Unknown historical strings cannot be safely assigned to a generic category without a product decision. The FK therefore remains nullable; making it required needs a separate reconciliation/migration step. Unknown legacy writes remain accepted for compatibility.
2. **Classification is not provisioning.** GCP remains the sole active provider. A generic category or code grants no provisioning capability and does not map automatically to a GCP service. No SDK, provider plugin framework, AWS/Azure project or deployment logic is introduced.
3. **Legacy responses do not expose the new FK.** This preserves their exact shapes. A future API contract can expose classification when the frontend adopts the catalog. Explicit null currently means omission and cannot independently clear an unchanged explicit classification.
4. **Frontend documentation correction.** Earlier documentation assumed Godot loaded `/resources`; current source inspection did not find such a client. The enum is not an inventory of persisted API strings. The updated architecture page records the observed behavior rather than that assumption.
5. **Rollback loses new classification data.** It preserves historical resource/design data, but cannot reconstruct manually assigned generic classifications from arbitrary legacy strings.
6. **Environment reproducibility.** The non-root account and extracted PostgreSQL tools are runtime-only setup for this container. Rebuilding it removes that setup. A future devcontainer maintenance task can declare non-root tooling explicitly; this issue does not alter its configuration.
7. **Unrelated security work remains separate.** No authentication or credential remediation was added. Existing development credential concerns are not solved by a type catalog. No sensitive values are reproduced here, no credentials were revoked/deleted, no stash was removed, no shared history was rewritten, and no Docker container or volume was removed.

## References

- [Issue #9](https://github.com/dexterBEN/blacksmith/issues/9).
- [Updated backend architecture, UML, ERD and contracts](docs/backend/current-architecture.md).
- [Official PostgreSQL Debian package repository](https://apt.postgresql.org/pub/repos/apt/).
