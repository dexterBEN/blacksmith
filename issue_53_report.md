# Issue #53 — Multi-resource persistence in the 3D editor

Multiple Cloud Storage placements can now be saved to one Design and restored after a complete application restart. Each placement retains its own server identity, configuration, revision and ETag. Earlier successful writes remain confirmed when a later placement fails.

## Baseline and scope

- Base `83000ccc5742003e90954be93872580c61d218d9`, merged PR #52, verified through GitHub metadata.
- The existing clean `issue_53` branch was rebased onto updated master; no stashes were used.
- Frontend integration only: no JSON dialog, deployment, provider calls, live development migration or visual redesign.
- Both palettes continue local placement. Header Save uses legacy metadata-only POST for unconfigured placements, as explicitly permitted by the issue. The API chooses these server IDs; in-session uncertainty blocks further writes and uses strict read-back. No project/bucket/region is fabricated.
- Explicit configured intents use stable client UUIDs, scoped conditional PUT, and aggregate GET/list including configuration/revision/ETag. These are repository/test/future-dialog capabilities, not an added configuration UI.
- IsomapGridBloc owns immutable rich Resource entries; the old `tiles` kind map is a derived immutable rendering projection for the existing 3D and legacy 2D adapters.
- Persisted kind replacement is blocked; metadata-only edit/deletion synchronization remains unsupported rather than silently rewriting saved data.

## Implementation

- `IsomapGridState.resources` is the sole live grid snapshot. Immutable `PlacedResource` values distinguish local intent keys from server IDs; `ResourceConfiguration` deeply freezes documents. The old `tiles` map is a derived immutable projection for the unchanged 3D and legacy 2D renderers.
- `ResourceRepository` owns the HTTP/JSON contracts: full aggregate list/GET, metadata-only legacy create, configured conditional create/update, revision/ETag handling, sanitized errors, complete-response validation and duplicate identity/position rejection. No Godot dependency or automatic retry is introduced.
- `DesignCubit` captures Save snapshots and tracks per-resource confirmation and uncertainty in memory. It verifies the complete confirmed baseline, writes changed supported resources sequentially, then confirms through Design/resource reads. Check Save performs reads only, even when recovery succeeds. A newer local configuration draft survives confirmation of an earlier snapshot.
- Open validates the entire response before one acknowledged BLoC restore. Unsupported type/version/state, invalid coordinates, duplicate identity/position or incomplete data leave the previous Design/grid intact. Repeated Open completes even when the snapshot is unchanged.
- The two existing palettes still share one placement action. Replacing an unsaved cube works for all four GCP kinds; replacing a persisted kind is disabled with an explanation. Header feedback distinguishes saved placements, missing configuration and deployment.
- Tests cover the aggregate wire contract, rich immutable state, partial success/retry, lost responses, stable identities and configuration-only edits. Native persistence checks use the real API/PostgreSQL, a complete process restart, actual screenshots, SQL verification and network tripwires.

## Deliberate boundaries and observations

1. The reference image depicts a configuration dialog and Save & Deploy, which are outside this issue. No new dialog, deployment button, provider operation or visual redesign was added.
2. Palette placements still lack required configuration fields. As explicitly allowed by the issue, their Save uses the existing metadata-only POST and the backend generates the server UUID. Local intent keys remain stable; they are not falsely presented as preassigned server IDs. Explicit configured intents use their original client UUID with `If-None-Match: *`, or the saved ETag with `If-Match` for updates.
3. For a lost legacy POST response, recovery accepts only a unique, exact matching new revision-1 row absent from the preflight snapshot. This verifies the observed desired state, not causal authorship: a concurrent identical create cannot be distinguished. The guard blocks new writes until resolved, but is memory-only. Crash recovery of an unacknowledged legacy POST is not guaranteed; a durable journal is deliberately deferred.
4. Saving is per Resource, not a transaction across the entire Design. If A succeeds and B fails, A remains confirmed and a subsequent deliberate Save targets B. Confirmed IDs are never replaced to avoid conflicts. Conflicts require read-back/Open rather than silent overwrites.
5. Only Cloud Storage persists in this slice. Other GCP kinds remain available locally. Persisted deletion, moving/kind replacement and unsupported configuration editing are not implemented or silently treated as saved.
6. The development database lacks the existing configuration/occupancy migrations. They must be applied deliberately before this workflow is used there. This task applies migrations only to an isolated temporary test database; it does not change the development database.

## Validation before the implementation commit

- Dart analysis: no issues. Unit/repository suite: **154 passed**.
- Fresh bindings generation: success, 172 outputs. The locked generator warns that its analyzer predates the installed SDK; dependencies were not upgraded.
- Real configured API integration: success, including original-UUID recovery after losing a committed PUT response, revision conflict, occupied tile and no-op handling.
- Native two-resource journey: success. A real second POST response was dropped, read-only recovery produced no third POST, and a second Godot process restored both IDs plus one explicit fixture configuration. Repeat Open and scene reload preserved the expected resources. Native 960 × 640 and desktop screenshots were inspected.
- Independent SQL verification: exactly two owned Resources at `(x=3,y=2)` and `(x=1,y=4)`, one configuration. The preliminary test API was stopped and its owned disposable database removed.

These are working-tree checks. The final results below will identify the committed source and the checks rerun from its fresh export.

## Final committed-state validation — pending

- Fresh bindings, Dart analysis and unit/repository tests.
- Isolated real API/PostgreSQL integration with all required migrations.
- Native two-resource Save/Quit/Open/repeated Open and failure/reconciliation checks.
- Native desktop/minimum-size workspace, New Design and legacy 2D regressions.
- Final committed-state runs, database invariance check and exact evidence/commands.

No passing final-validation claim is made in this implementation commit. The final report update will record actual outcomes and any failures without changing the tested frontend source.
