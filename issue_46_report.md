# Issue #46 — optional ResourceConfiguration and JSONB persistence

Resources previously stored placement metadata only. This change adds an optional, versioned JSON configuration document per Resource, while existing API requests/responses and editor behavior remain unchanged.

Implements [Issue #46](https://github.com/dexterBEN/blacksmith/issues/46).

Scope: backend persistence foundation only. The issue's generic `ResourceConfiguration` / `jsonb` choice supersedes the audit's earlier typed Cloud Storage suggestion. Multiple independently configured Resources in one Design are supported; no one-resource-per-Design or tile-uniqueness invariant is introduced.

## Implementation

| File | Change |
|---|---|
| [ResourceConfiguration.cs](backend/src/Blacksmith.Domain/Entities/ResourceConfiguration.cs) | New entity: ResourceId, Resource navigation, SchemaVersion, Configuration. |
| [ResourceEntity.cs](backend/src/Blacksmith.Domain/Entities/ResourceEntity.cs) | Nullable configuration navigation; existing field definitions unchanged. |
| [BlacksmithDbContext.cs](backend/src/Blacksmith.Infrastructure/Persistence/BlacksmithDbContext.cs) | DbSet and explicit table/column mapping, PK/FK, cascade and positive-version check. |
| [Migration](backend/src/Blacksmith.Infrastructure/Migrations/20261025205111_AddResourceConfigurations.cs) | One additive migration, generated Designer and updated model snapshot. |
| [ResourceConfigurationTests.cs](backend/tests/Blacksmith.PostgreSql.Tests/ResourceConfigurationTests.cs) | Seven real PostgreSQL tests covering storage, relationships, migration and HTTP compatibility. |
| Existing migration/model tests | Expected migration/entity counts updated; original assertions retained. |

Database shape:

```text
resources."Id" (uuid PK)
    1 ─── 0..1 resource_configurations
                 resource_id    uuid PK/FK, ON DELETE CASCADE
                 schema_version integer NOT NULL, CHECK > 0
                 configuration  jsonb NOT NULL
```

The FK uses the actual existing quoted `resources."Id"` column. Design → Resource deletion remains restrictive. Resource deletion removes only its owned configuration; it does not delete the Design, other Resources or any cloud resource. Existing rows receive no synthetic configuration or deployment state. The migration's Down removes only the newly introduced table and its documents; downgrade checks run exclusively on disposable databases.

## JSON representation and versioning

`Configuration` is an immutable .NET string containing **raw JSON document text**, explicitly mapped with `HasColumnType("jsonb")`. Npgsql sends that document as PostgreSQL JSONB; it is not stored in a text/bytea column and is not JSON-serialized a second time. Native `jsonb_typeof` and JSON-path checks prove an object remains an object. This is a supported [Npgsql string mapping](https://www.npgsql.org/efcore/mapping/json.html#string-mapping).

This keeps EF's standard string snapshot/change tracking and existing SQLite HTTP regression fixtures compatible. No JSON DOM ownership/disposal, mutable dictionary comparer, dynamic-JSON opt-in, dependency upgrade or provider/schema registry is needed. Update by assigning new raw document text to the tracked configuration entity, then SaveChanges; the existing PK row is updated.

Compare JSON **values**, not original whitespace/key order: PostgreSQL JSONB normalizes its representation. Tests cover nested objects/arrays, Unicode, numbers, booleans and JSON null, plus root arrays/scalars and a large integer. JSON null and SQL NULL are distinct; the latter is rejected.

SchemaVersion must be explicitly set to a positive integer. It describes document format, separately from EF migration history and any future concurrency/deployment revision. No duplicate version field is injected into the JSON. This foundation accepts syntactically valid JSON of any root type and any positive version; it does **not** assert that a document is complete or valid Cloud Storage configuration. There is no new public JSON ingress. The subsequent API issue must validate type/version/fields, payload size/depth and secret exclusion before accepting untrusted documents. Legacy metadata update semantics are unchanged.

## Compatibility evidence

The new PostgreSQL tests verify:

- A Resource without configuration still loads with a null navigation; configuration columns are required and the native column type is JSONB.
- Two Resources within one Design retain independent documents, including when their historical tile positions coincide. Replacing one document/version leaves Resource metadata and the other document unchanged.
- The PK rejects duplicate configurations, the FK rejects orphans, and invalid versions, malformed JSON and SQL NULL are rejected by PostgreSQL.
- An unloaded dependent is removed by database cascade when its Resource is deleted; sibling records survive and Design deletion remains restricted.
- Upgrading a populated database from `20261019094942_AddResourceTypeCatalog` preserves complete Design, Resource and catalog rows, including Unicode, whitespace, unknown types, duplicate positions and out-of-range historical coordinates. No configuration is backfilled. Isolated downgrade/re-upgrade preserves the original rows.
- Existing Resource/scoped GET response field sets remain unchanged; legacy PUT preserves configuration, POST still permits unconfigured rows and DELETE handles the dependent lifecycle. The HTTP test's cloud fake reports zero calls.

## Validation

Environment: existing backend Dev Container `d26cb899e251`, .NET SDK **8.0.426**, EF Core/Npgsql **8.0.11**, PostgreSQL **16.15**. The stopped Dev Container was restarted; no container or volume was removed.

The temporary backend copy and logs are under `/tmp/blacksmith-issue46-work-xrjed51h`. EF migration generation used an intentionally unreachable connection (`127.0.0.1:1`) and an unusable GCP credential path. No database was migrated by the generation command.

Initial offline restore failed because test dependencies were absent from the container cache. Restoring the already-declared packages from NuGet resolved this; no package versions or project files were changed. Preliminary Release build: 0 warnings/errors. Preliminary tests: **31 application + 49 integration + 18 PostgreSQL = 98 passed, 0 failed, 0 skipped**.

Committed-state validation used a fresh Git export of **`70716bdcb566a8840d8509732b5fe1e8b4ba1028`**, with no copied build outputs or uncommitted source. Exact backend Git tree: **`c1b06fa6c0d3e406265905d1ce3e9474ab0b4a0d`**. The report-only follow-up preserves that tested backend tree.

| Final check | Actual result |
|---|---|
| Restore from populated local package cache | Exit 0 |
| Release solution build | Exit 0; 0 warnings, 0 errors |
| Application tests | 31 passed, 0 failed, 0 skipped |
| Integration/HTTP/model tests | 49 passed, 0 failed, 0 skipped |
| Real PostgreSQL tests | 18 passed, 0 failed, 0 skipped; includes 7 new configuration tests |
| Total | **98 passed; no tests skipped** |
| Development schema/history check | Unchanged: original four migrations; configuration table absent |
| Temporary test database cleanup | No `blacksmith_issue7_*` databases remain |

Final logs and all three TRX files are retained under `/tmp/blacksmith-issue46-final-_6p72wjk`; commands/results metadata is in `/tmp/blacksmith-issue46-final.json`. Temporary logs are local evidence, not committed artifacts. No build or test failure occurred after dependency restoration.

Actual generation command, executed from the temporary backend root:

```bash
dotnet ef migrations add AddResourceConfigurations \
  --project src/Blacksmith.Infrastructure --startup-project src/CloudServices.Api \
  --context BlacksmithDbContext --configuration Release --no-build --no-color
```

Reproduction of backend validation from a clean committed export, inside the existing SDK environment:

```bash
# Prerequisite: BLACKSMITH_TEST_POSTGRES is a private environment variable
# containing an administrative connection to postgres on the test-capable server.
# Never print it. The existing fixture creates/drops only its random test databases.
dotnet restore BlacksmithBackend.sln --source /root/.nuget/packages -p:NuGetAudit=false
dotnet build BlacksmithBackend.sln --configuration Release --no-restore --nologo
for project in Blacksmith.Application.Tests Blacksmith.IntegrationTests Blacksmith.PostgreSql.Tests; do
  dotnet test "tests/$project/$project.csproj" --configuration Release \
    --no-build --no-restore --logger 'trx;LogFileName=results.trx' \
    --results-directory "/tmp/blacksmith-issue46-results/$project" --nologo --verbosity minimal
done
```

The test runner derives its administrative connection from the existing container environment without printing it, sets its database to **postgres**, and passes it through the environment. Every PostgreSQL test creates its own `blacksmith_issue7_<random-guid>` database using the existing guarded fixture. The ordinary application connection is replaced with an unreachable address during testing, and GCP credentials are disabled. Migration/down tests never target `blacksmith_db`.

## Scope and remaining work

No controller, DTO, application service, provider implementation, frontend, credential or Dev Container configuration changes. No GCP calls, UI/status badges, secret data, concurrency protocol, tile uniqueness or service-specific validation were added. The reference image is future UX context only; there is no visual work in this PR.

The development DB initially has four migrations and no `resource_configurations` table. The new migration is deliberately **not applied to it** in this issue. Automatic migration at API startup is unchanged. Frontend/Godot tests are not rerun because their source tree is unchanged.

Follow-ups remain the issue's milestones B/C/D: validated API contracts; reliable multi-resource persistence and historical-position analysis; then the JSON configuration dialog. Save and Deploy remain separate.

Branch procedure: `master` was already current at `e55b149` after `git pull --rebase origin master`; work is on `issue_46`. Existing stashes and unrelated refs are preserved. No automatic merge.
