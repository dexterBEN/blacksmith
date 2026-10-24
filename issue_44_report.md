# Issue #44 — First persistent 3D Design workflow

## Contract audit (baseline `1f3f9f6`)

- `POST /designs` accepts `{name, description?}` and returns 201 with server-generated
  `id`, `name`, `description`, `createdAtUtc`, `updatedAtUtc`. `GET /designs`,
  `GET /designs/{id}` return the existing Design DTO; invalid/missing GUIDs yield 404.
- `POST /resources` accepts `designId`, `resourceTypeId`, `name`, integer `x`, `y`,
  and legacy/provider-specific `type`. The API generates the Resource GUID.
  `GET /resources`, `GET /resources/{id}`, `PUT /resources/{id}`, and
  `DELETE /resources/{id}` exist. Create/read responses omit ownership/type FK.
- `GET /designs/{id}/resources` returns the authoritative ownership list, including
  `id`, `designId`, `name`, `x`, `y`, `type`, `createdAtUtc`, but no `resourceTypeId`.
  Save confirmation must use this scoped read-back, not only the POST response.
- `GET /resource-types` and `GET /resource-types/{id}` return `id`, `code`,
  `displayName`, `category`. Seeded codes are `virtual-machine`, `storage`,
  `database`, `network`, `gateway`, `load-balancer`.
- Cloud Storage mapping: provider-specific persisted `type = gcp.storage.bucket`,
  generic catalog `code = storage`. This legacy/provider type is already exercised
  by backend tests; explicit catalog IDs are supported with unknown legacy codes.
  Resolve the storage catalog GUID at runtime, never invent or hardcode it.
- Coordinates: `GridPos(row: 2, col: 3)` maps to `{x: 3, y: 2}` and back.
- Resources belong to exactly one Design; deleting a nonempty Design is restricted.
  There is no unique `(design_id, x, y)` constraint or idempotency token. The API
  accepts duplicate positions and arbitrary integer coordinates. Frontend reads
  must validate the supported grid bounds and reject duplicates/unsupported data.

## Implementation approach and limits

Retain DesignCubit as the one coordinator. Repositories own HTTP, JSON, catalog
resolution and persisted-record validation. IsomapGridBloc remains the sole visible
local grid state, with a narrow hydration event. Save takes an immutable snapshot;
Open hydrates only after all reads and validation succeed. A single grid subscription
updates save/unsaved feedback and is cancelled on Cubit shutdown.

Add only Save and Open-by-ID controls to the existing dark workspace. Keep four
local placement kinds, native viewport/camera/input mapping, New Design behavior,
and the legacy 2D scene. Persist only an empty Design or one Cloud Storage cube;
reject multi-resource/other-kind saves and replacement/deletion synchronization.

Before POST, read existing Design resources. After POST, independently read the
Design ownership list and confirm the exact one record. Disable duplicate requests
while busy and unchanged repeated saves. An ambiguous write is never blindly
retried: retain a per-Design attempted-write guard and expose read-only reconciliation.
An empty read while the outcome is unknown does not prove that a late commit cannot
still occur. Without backend idempotency, this cannot provide a cross-process or
multi-writer exactly-once guarantee. This API limitation is explicitly raised before
implementation; the issue prefers the existing contracts and excludes new uniqueness
features. No backend production change or migration is planned unless this scope
is explicitly revised. The user explicitly selected the existing API with guarded
read-back recovery; no backend idempotency extension is authorized for this slice.

## Validation

Implementation and validation in progress. Results will be recorded after checks.
Use an isolated PostgreSQL database with existing migrations, never the development
database. No GCP credential or cloud operation is needed. Dedicated Resource rows
must be deleted before their Design during test-data cleanup.

## Branch and preservation

Started with a clean `issue_42`, switched to `master`, ran `git pull --rebase origin
master` (fast-forward to `1f3f9f6`), then created `issue_44`. Preserve all three
existing stashes and unrelated branch tips. No automatic merge.
