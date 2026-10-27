# Issue #58 — First explicit Cloud Storage Save & Deploy

Implementation is ready for committed-state validation on `issue_58`, created from the user's already updated master (`311ab18`). Existing stashes are preserved. No live GCP request or development DB migration has been authorized or executed.

## Design and identified risks

- The old `/cloud_services/create-bucket` bypasses resource identity and authorization. It is retired with HTTP 410; cloud ping no longer resolves ADC. Deployment is disabled by default and requires a Development environment, an external local deployment token, an approved-project allowlist and explicit mutation consent.
- One configured PUT command saves Resource/configuration and a durable deployment intent in an outer DB transaction, commits, then executes GCP separately. No distributed atomicity or automatic bucket compensation is claimed.
- An operation binds Resource/Design IDs, exact saved revision, canonical configuration, target, server ownership proof and outcome. Request-attempt IDs deduplicate explicit retries; leases expose interrupted execution as unknown. GET/Open never calls Google. Reconciliation only reads the original bucket; known failures can be explicitly retried with the same target and ownership marker.
- Provider integration applies location, STANDARD, uniform access and enforced public access prevention. It resolves the project ID/number before bucket creation, then verifies bucket project number, resource/ownership labels and settings. Matching a global bucket name alone is insufficient. ADC/auth material is neither stored in configuration nor returned/logged.
- A Resource's deployment target is locked once an operation exists; Save-only remains available for later edits, but retargeting deployment to another configuration requires separate work. Durable deployment records prevent silent Resource deletion or Design reassignment.
- The existing native JSON modal retains Save configuration and adds reviewed/confirmed Save & Deploy with readable persisted outcome. No rendering redesign or status micro-icons are planned.

## Preliminary validation before freezing the implementation

- Backend build: 0 errors/warnings; application tests: 96 passed; HTTP tests: 88 passed before two additional cases; PostgreSQL: 42 passed on isolated databases.
- Fresh Dart bindings generated; Dart analysis: no issues; full Dart suite: 199 passed before one additional case.
- Native Godot fake-provider Save/unknown/reconcile/Quit/Open passed with separate process IDs. The final committed-state journey also exercises provider rejection and an explicitly consented retry.
- The two old HTTP model-contract failures were expected-count assertions (6 → 7 migrations, 4 → 6 entities), not runtime failures. PostgreSQL fixtures were corrected to avoid reinserting the Legacy Design seeded by migrations; migration-count assertions were updated.

## Committed-state validation still to record

- Backend unit/HTTP/PostgreSQL tests and migration on disposable databases only.
- Dart analysis/tests and native fake-provider Save/Deploy/Quit/Open, workspace, New Design and 2D regressions from an exact committed revision.
- Live GCP smoke test remains **not authorized / not executed**. Before any real bucket creation, the owner must approve the exact project, identity, bucket name, region, possible costs and cleanup plan. Cleanup also requires separate approval; a DB containing a real/unknown cloud operation must not be discarded before ownership evidence is safely retained.

The final report will record the precise contracts, transition table, actual commands/results, failures, screenshots, migration/runtime prerequisites and remaining limitations.
