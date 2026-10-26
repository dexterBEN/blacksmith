# Issue #51 — Reliable atomic Resource persistence

Configured Cloud Storage Resources can now be created with a stable client UUID and saved atomically with their validated jsonb configuration. Conditional edits preserve identity and reject stale revisions. PostgreSQL enforces one persisted Resource per Design/tile, including writes through the existing metadata routes. This is backend groundwork; no cloud service is provisioned.

## Base, scope and decisions

- Issue: [#51](https://github.com/dexterBEN/blacksmith/issues/51#issue-6032716264), informed by [audit #50](https://github.com/dexterBEN/blacksmith/issues/50).
- Base: `808b81cb3d1b739bbc9e7b74a6977d5af7d7ec33`, containing merged PRs #47/#49. Master was updated with pull --rebase; the existing clean `issue_51` branch was rebased onto it (already current).
- Preserved Controller → Service → Repository/EF responsibilities. Configured operations extend the existing ResourceService/ResourcesController; the service implementation is split into a partial file for readability. No parallel provider API, workflow engine, package or cloud dependency was added.
- Used the issue's scoped PUT, while keeping existing GET routes with an opt-in aggregate representation. The configuration wrapper follows PR #49 rather than the illustrative flattened example.
- Selected If-None-Match:* for create and a single strong If-Match Resource revision tag for edit. No expectedRevision body field or client journal was added.
- Coordinates remain **signed Int32**, including negatives; overflow/fractional/string values are rejected. The temporary 6×6 frontend size is not a SQL/API coordinate limit. Name is a display label, distinct from bucketName.
- Save & Deploy may be a later single UI action, but database persistence and a Google provider outcome cannot be one distributed ACID transaction. This increment contains only persistence.

## Public contracts

```http
PUT /designs/{designId}/resources/{resourceId}
If-None-Match: *                   # create only
# or If-Match: "resource-<UUID without dashes>-r<revision>" for edit
```

Body:

```json
{
  "name": "My storage display label",
  "type": "gcp.storage.bucket",
  "resourceTypeId": "10000000-0000-0000-0000-000000000002",
  "x": 3,
  "y": 2,
  "configuration": {
    "schemaVersion": 1,
    "configuration": {
      "projectId": "example-project-123",
      "bucketName": "blacksmith-example-assets",
      "location": "europe-west9"
    }
  }
}
```

Creation returns 201; changed edit and semantic no-op return 200. `X-Resource-Write-Outcome` distinguishes created/updated/unchanged. No-op retains revision after checking the current precondition. Existing create ID and stale revision return 412 with resource_exists/revision_conflict; occupied tile returns 409 tile_occupied. Missing precondition returns 428; invalid payload/precondition returns 400, missing Design/catalog/edit target 404, wrong owning Design 409, oversized body 413. Application errors have stable code/error fields; malformed JSON retains framework validation responses.

`GET /resources/{id}?include=configuration` returns canonical metadata, Design/catalog IDs, configuration state/document and revision, plus the edit ETag. `GET /designs/{id}/resources?include=configuration` returns all such aggregates ordered by Y/X/ID, loading metadata/configuration/catalog in one query. Plain legacy DTOs are unchanged. Unconfigured historical Resources remain readable with absent/null configuration; unsupported historical documents are classified without exposing their raw JSON. No deployed status is synthesized.

The existing v1 validator is reused: required identifiers/region, explicit three-location subset, canonical fixed STANDARD/UBLA/PAP settings, strict keys/duplicates/depth/size, no softDeleteRetentionDays or credentials. SchemaVersion remains separate from jsonb and from the new Resource revision. The outer configured envelope is also strict and limited to 16 KiB. Canonical create timestamps match PostgreSQL precision and read-back.

Full examples, recovery semantics, status codes and operator guidance: [resource-persistence-api.md](docs/backend/resource-persistence-api.md).

## Atomicity, compatibility and migration

- Resource metadata and configuration insert/update commit in one transaction. Child-write failure rolls back parent metadata and revision as well; no compensating DELETE is issued.
- Existing parent-row locks serialize configured, metadata and configuration edits. Named PK/tile violations handle concurrent creates where no row can yet be locked. Revision is an EF concurrency token as an additional safeguard.
- Legacy metadata/configuration PUTs advance revision while preserving existing JSON contracts and configuration/type safeguards. They remain unconditional last-write-wins; new conditional clients detect their changes. Resource DELETE now takes the same parent lock, keeps its configuration cascade and leaves siblings intact. Design deletion remains restrictive.
- Migration **20261026040000_EnforceResourceIdentityAndOccupancy** takes a writer-conflicting table lock, checks historical duplicates and stops with a clear diagnostic before adding revision/default 1 and the unique `(design_id,x,y)` index. It never deduplicates, moves or deletes data and adds no viewport CHECK.
- Historical tests that used same-tile occupants as unrelated fixture data now use distinct coordinates. A dedicated migration fixture retains duplicate rows and proves migration refusal without data/schema loss. Old-schema seeding uses actual historical columns; original metadata preservation assertions remain, with the new revision tested separately.
- Migration/model snapshot consistency is verified by EF's HasPendingModelChanges checks. EF CLI is absent in the current Dev Container; the small migration/snapshot delta was authored directly, without installing tools or changing container configuration.

## Validation

Working-tree verification: **210 passing tests** (96 application, 76 HTTP integration, 38 real PostgreSQL), zero failures/skips in the latest run. Release build: zero warnings/errors. Final committed-state verification is pending and will be recorded before publication.

Tests run inside the existing backend Dev Container (SDK 8.0.426) against cached packages and disposable random PostgreSQL databases, not blacksmith_db. The container had been stopped and was restarted; the PostgreSQL/pgAdmin containers were already running. The ordinary API connection is overridden to an unused address and the credential path is nonexistent. Cloud services are replaced by fail-closed/recording test doubles; new HTTP/PostgreSQL scenarios assert zero cloud calls. No actual provider request is made.

Coverage includes two independent configured Resources; stable-ID read-back after discarding a successful response; canonical/no-op/edit responses; stale/double updates; concurrent same-ID and same-tile creation; an observed competing PostgreSQL row-lock wait; rollback after child insert/update failure; concurrent parent deletion; legacy POST/PUT occupancy and owner changes; revision advancement through legacy routes; missing/invalid/secret-bearing payloads; populated migration/backfill, duplicate preflight failure and raw database uniqueness; legacy unconfigured/unsupported reads and deletion semantics. Existing ownership/catalog/configuration regressions remain enabled.

Initial test runs found 16 failures, then one remaining fixture failure. They exposed old migration/index counts, incidental duplicate tiles, old-schema seeding, a fixture SQL JSON literal and create/read timestamp representation differences. These were corrected; no failing/skipped check is being presented as passed. The timestamp fix applies to the new aggregate representation; the legacy DTO contract remains intact.

## Development database and remaining work

Read-only preflight: blacksmith_db still has the four earlier migrations, no resource_configurations table and no duplicate tiles. Metadata fingerprints were recorded privately for post-test comparison. **No development migration is authorized or performed by this issue.** Before running this backend manually against that database, separately back it up/test restoration, inspect duplicates, apply PR #47's existing migration then this issue's migration, and verify counts/FKs/index/read-back. See the operator procedure in the contract document. The API does not migrate on startup.

Known limits and next steps:

- The caller must retain its UUID and intended canonical payload across uncertainty. Read by that original ID first; never blind-POST a new identity. This backend does not preserve a lost client's draft/ID, supply exactly-once execution, or prevent resurrection if a create is replayed after deletion. No client journal, server ledger/tombstones, job queue or activity log is introduced.
- Design creation still uses its existing non-idempotent server-ID POST. Recovery of Resource writes does not solve an interrupted New Design.
- No whole-Design batch transaction or revision is added. Saving A then failing B leaves A confirmed; the frontend must track per-resource outcomes and avoid claiming global success.
- Next frontend work: richer BLoC entries, stable identity/configuration/revision, multi-resource Open/Save/reconciliation, preserving legacy 2D and existing scene/input behavior. The JSON editor, confirmed-save cube appearance and icons remain later work.
- Future Save & Deploy requires explicit authorization and a separately durable provider outcome (including failure/unknown), even if triggered by one UI request. No provider/deployment fields or operations are implemented here.
- No Godot/Dart, assets, Dev Container files, credentials, shared history or stashes were changed. No automatic merge.
