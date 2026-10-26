# Issue #55 — Cloud Storage JSON configuration and confirmed Save

Implementation and validation are in progress on `issue_55`, created from the user's already updated `master` (`b1b4cb5`). No stashes were applied or removed.

## Confirmed scope and contracts

- One native scrollable JSON editor in the existing dark workspace; Save only, no GCP calls or deployment UI.
- The actual v1 envelope is `{schemaVersion: 1, configuration: {...}}`, not the flattened illustrative issue sample.
- Required nonsecret identifiers: `projectId`, `bucketName`, `location`. The backend accepts only `europe-west9`, `us-central1`, `northamerica-northeast1`; it fixes STANDARD, uniform bucket access and enforced public access prevention. Unsupported/duplicate fields and credentials documents are rejected. The backend remains authoritative.
- Atomic configured writes use `PUT /designs/{designId}/resources/{id}` with `If-None-Match: *` for create or `If-Match` revision tags for edits. Full GET/list with `include=configuration` confirm canonical data before any new cube appears.
- A single modal draft belongs to `DesignCubit`; `IsomapGridBloc` remains the sole renderable grid state. HTTP and JSON parsing stay in the repository. The draft captures Design/tile, stable UUID and original revision; cancellation and failed writes do not place a provisional cube.
- New templates contain clearly labelled illustrative identifiers, requiring user review. Existing unconfigured records open with empty required identifiers, preserving their server identity and existing cube until explicit confirmed configuration.
- Other kinds keep local placement. Cloud Storage now requires an active Design and an empty or Cloud Storage tile. It does not silently replace a different local kind. The header's legacy metadata Save remains available for old unconfigured local snapshots; it skips already confirmed configured rows.
- Unknown writes retain their intent and stable ID in memory; Check Save is read-only. Closing an uncertain form retains the shared recovery guard. Durable crash journalling remains out of scope.

## Validation so far

- Working-tree Dart analysis: no issues. Unit/repository suite: **192 passed**.
- Real API/PostgreSQL repository integration passed, including rejected configured creation/update without partial changes.
- Initial native Save phase passed (modal/scroll/Escape, real rejection, delayed/lost responses, both configured resources, edit/no-op and legacy fixture). The combined process was interrupted with exit 143 during Open, without a logged Dart/Godot cause; restart is not yet claimed as validated. The runner now supports separate Save/Open invocations and final validation will use these phases.
- Final committed-state bindings, analysis/tests, real API/PostgreSQL atomic rollback/round-trip, native form/Save/Quit/Open, New Design/workspace/legacy 2D checks and exact evidence are pending.
- No development database migration or GCP operation has been performed.

The final report will replace this in-progress section with actual committed-state results, commands, screenshots, prerequisites and limitations. No final-validation success is claimed yet.
