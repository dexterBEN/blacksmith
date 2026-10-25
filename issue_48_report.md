# Issue #48 — Validated ResourceConfiguration API (Save-only)

Existing Cloud Storage Resources can now save, read and replace their bucket configuration through dedicated HTTP endpoints. The configuration is validated locally and stored as native PostgreSQL `jsonb`. Saving never provisions a bucket.

## Base and scope

- Issue: [#48](https://github.com/dexterBEN/blacksmith/issues/48).
- Branch: `issue_48`, created after updating `master` with `git pull --rebase origin master`.
- Base: `5699f63f86635ea7740dce938e4dcb163d421692`, containing merged PR #47 and its optional ResourceConfiguration relationship.
- Existing migration: `20261025205111_AddResourceConfigurations`. No new entity, column, migration, package or SDK is added.
- No Godot/Dart, cloud provisioning, credentials, development database or Dev Container changes.

## API and validation

`GET /resources/{resourceId}/configuration` returns the canonical object, schemaVersion and owning resourceId. Unknown Resources and Resources without configuration return 404; no synthetic configuration is created.

`PUT /resources/{resourceId}/configuration` creates or replaces configuration for an existing eligible Resource, returning 200 in both cases. A valid request for an unknown Resource returns 404. Resource identity, Design, name and coordinates are preserved.

Minimal request:

```json
{
  "schemaVersion": 1,
  "configuration": {
    "projectId": "example-project-123",
    "bucketName": "blacksmith-example-assets",
    "location": "europe-west9"
  }
}
```

The server obtains Resource.Type, DesignId and optional catalog classification from PostgreSQL. Exact provider type `gcp.storage.bucket` is required; if a catalog reference exists, its code must be `storage`. Generic classification alone does not establish a GCP service. Legacy rows with no classification remain supported.

Validation is deliberately narrow:

- Only JSON integer schemaVersion 1 and an object configuration are accepted.
- Required projectId uses a conservative 6–30 character lowercase project-ID format; bucketName uses a conservative 3–63 character lowercase letter/digit/hyphen subset. Reserved Google name patterns are rejected.
- Allowed regions: `europe-west9`, `us-central1`, `northamerica-northeast1`. No implicit region or multi-region.
- Omitted fixed settings are materialized as `storageClass: STANDARD`, `uniformBucketLevelAccess: true`, `publicAccessPrevention: enforced`. Explicit differing values or nulls are rejected.
- **softDeleteRetentionDays is unsupported**, including value 7. It is rejected rather than silently defaulted.
- Strict field allowlists apply to the envelope and configuration. Unknown fields, client type/Design overrides, duplicate logical fields, case variants and escaped duplicate names are rejected.
- Limit: 16,384 UTF-8 request bytes, maximum validation depth 8. Endpoint limits and application checks are combined without changing global JSON settings.
- Obvious credential fields cannot pass the allowlist. This is not a general secret scanner; clients must not encode credentials into allowed resource names. No request-body logging is introduced; application validation messages do not include submitted values.

Responses contain a JSON object, not an encoded JSON string; schemaVersion remains separate from the jsonb document. A detached JsonElement avoids returning a disposed JSON document. Full request/response examples and status semantics are documented in [the API contract](docs/backend/resource-configuration-api.md).

The regional and naming subsets were checked against Google's [locations](https://docs.cloud.google.com/storage/docs/locations), [project IDs](https://docs.cloud.google.com/resource-manager/docs/creating-managing-projects) and [bucket naming](https://docs.cloud.google.com/storage/docs/buckets#naming) documentation. These checks do not establish project existence, global name availability, IAM access or deployability.

## Compatibility and transaction behavior

- Existing Resource metadata DTOs and response shapes remain unchanged. Metadata-only PUT preserves any configuration.
- A configured Resource cannot change service type through metadata-only PUT, or acquire an incompatible bucket catalog classification. The request returns 400 and leaves prior state intact. Unconfigured Resource type editing remains available.
- Configuration PUT is a complete replacement. There is no PATCH, configuration DELETE, implicit Resource creation or cross-Resource write.
- Existing Resource deletion still cascades to its own configuration; sibling Resources/configurations are retained. Design deletion remains restrictive.
- Configuration and metadata updates take a short PostgreSQL parent-row lock inside a transaction. This prevents conflicting first inserts and the type/configuration race without adding schema or changing public contracts. Rejected operations release the transaction when their request scope is disposed.
- This does **not** implement stale-editor detection, ETags, revisions, compare-and-swap or retry reconciliation. Valid overlapping writes use last successful write wins.
- Historical unsupported configuration is not returned unvalidated: GET returns a generic 409. An explicit complete valid v1 PUT can replace it on an eligible Resource. GET may materialize omitted fixed settings in its response without updating the historical row.

## Files and responsibilities

| Area | Changes |
|---|---|
| API | Dedicated ResourceConfigurationsController and scoped DI registration; legacy controllers unchanged. |
| Application | Configuration response, service/interface, two narrow exceptions and CloudStorageConfigurationV1 validation helper. |
| Existing Resource service/repository | Configuration access and transactional parent lookup; metadata compatibility guard; no JSON/HTTP handling added to the domain. |
| Infrastructure | EF repository uses the existing DbContext and jsonb mapping; transaction disposal also supports existing synchronous test scopes. |
| Tests | Validator cases, real HTTP contract tests using SQLite, real isolated PostgreSQL round-trip/rollback/cascade/concurrent-write tests; memory repository adapter updated. |
| Documentation | API contract, README link and this report. |

## Validation evidence

Validated implementation commit: **`94cd347a9a2782fe9b694027310841ae4424a146`**. A fresh `git archive` export of its committed `backend/src`, `backend/tests` and solution was built and tested outside the checkout. No pre-existing build output or uncommitted helper was included. The follow-up commit changes this report only; the delivered backend tree remains **`752fd9fcfe8bcd0922157e569ad07574d8f72eee`**, identical to the tested tree.

| Check | Actual result |
|---|---|
| Cached-package restore | Passed; no package additions/upgrades. |
| Full solution Release build | Passed; **0 warnings, 0 errors** (24.67 seconds). |
| Application suite | **82 passed**, 0 failed, 0 skipped. |
| HTTP integration suite | **65 passed**, 0 failed, 0 skipped. |
| Real PostgreSQL suite | **24 passed**, 0 failed, 0 skipped. |
| Total | **171 passed**, 0 failed, 0 skipped; 73 added cases over the 98-test baseline. |
| Cloud service counters | Zero calls in configuration HTTP/PostgreSQL tests; unexpected calls fail closed. |
| Development database | Read-only before/after migration checks equal: four older migrations, configuration table still absent. |
| Disposable databases | No `blacksmith_issue7_*` databases remain after the suites. |
| Git protection | All three stash object IDs/order preserved; unrelated branch references unchanged. |

The final run includes PostgreSQL tests that observe an actual competing database lock wait before releasing the first transaction. Both type/configuration race orderings and overlapping first PUTs pass. Preliminary validation also passed; there were no build or test failures during this increment.

Commands executed in the committed export's backend directory (the loop below spells out the same per-project test commands):

```bash
dotnet restore BlacksmithBackend.sln --source /root/.nuget/packages -p:NuGetAudit=false --nologo
dotnet build BlacksmithBackend.sln -c Release --no-restore --nologo
EXPORT=/tmp/blacksmith-issue48-final-z_bpr98l/backend
for suite in Blacksmith.Application.Tests Blacksmith.IntegrationTests Blacksmith.PostgreSql.Tests; do
  dotnet test "tests/$suite/$suite.csproj" -c Release --no-build --no-restore \
    --logger 'trx;LogFileName=results.trx' \
    --results-directory "$EXPORT/results/$suite" --nologo --verbosity minimal
done
```

Restore uses the container's existing package cache; online NuGet vulnerability auditing was disabled for this offline validation. Build logs, all three TRX files and parsed counters were retained outside Git at `/tmp/blacksmith-issue48-final-z_bpr98l`. Those local artifacts are temporary; the actual outcomes and source hashes above are recorded here for the PR.

Tests execute inside the existing backend Dev Container with .NET SDK 8.0.426 and PostgreSQL 16.15. PostgreSQL tests use randomly named disposable `blacksmith_issue7_<guid>` databases, inherited from the existing fixture naming scheme; only those databases are migrated and removed by their fixtures. The administrative connection targets `postgres`, never the developer's database. Connection credentials are passed privately through the process environment and are not included in commands or artifacts. The ordinary API database connection is set to an unused endpoint and the Google credential path to a nonexistent file; test factories replace cloud access with a fail-closed counter.

The complete suite includes existing Design/Resource CRUD, ownership/catalog and persistence regression tests. New coverage includes canonical/defaulted objects, independent configuration per Resource, exact legacy response fields, malformed/oversized/deep/duplicate/forbidden inputs, state preservation after rejection, unsupported stored documents, metadata editing, cascade, overlapping first PUTs and both type/configuration race orderings. Cloud-service call counters are asserted to remain zero.

## Observations and remaining prerequisites

1. **The development database has not received PR #47's migration.** The initial read-only check found the four earlier migrations and no `resource_configurations` table. Before manually using these endpoints or the updated Resource metadata PUT guard, apply the already existing migration through a separately authorized development-database operation. This issue does not do that.
2. The migration's jsonb column can hold historical arbitrary JSON; the API deliberately exposes only supported validated documents. Other services/versions need an explicit later contract.
3. Persistence/restore of multiple frontend cubes, tile occupancy uniqueness, a JSON editor, deployment indicators and real deployment remain separate increments. These endpoints alone do not establish the future end-to-end editor workflow.
4. The three-location subset and fixed policies are explicit MVP decisions. Expanding them requires a deliberate contract change; soft-delete policy still needs product approval.
5. All three existing stashes and unrelated work were preserved. No shared history rewrite, development-database migration, cloud resource operation or automatic merge was performed.
