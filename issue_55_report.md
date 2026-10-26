# Issue #55 — Cloud Storage JSON configuration and confirmed Save

Choosing Cloud Storage on a selected tile in an active Design now opens one scrollable JSON editor. Save configuration writes metadata and configuration atomically; a new cube appears only after canonical read-back. Multiple configured cubes and their documents survive a complete application restart. **Save does not deploy or contact GCP.**

## Changes and rationale

- `DesignCubit` owns one immutable `ResourceConfigurationDraft`, capturing Design, tile, original snapshot, UUID and revision. Pending requests block modal cancellation and duplicate submissions. Failed saves preserve text; uncertain results retain the original intent and expose read-only Check Save, including after closing the form. No extra Cubit or live grid map was added.
- `ResourceRepository` and `cloud_storage_configuration_document.dart` own HTTP/JSON, the editable template, v1 validation, duplicate-key detection, size limits and safe backend field messages. Editor validation rejects invalid/credential documents before writes; the backend independently validates all calls. Arbitrary response/input text is not reflected in errors.
- `ApplyConfiguredResource` publishes a verified Resource through `IsomapGridBloc` only if its captured tile is unchanged. Configuration editing retains identity, coordinates and revision/ETag; the existing rendering projection preserves unchanged mesh nodes.
- `resource_configuration_editor_3d.dart`, its native scene and the existing Design editor/palette route both Cloud Storage entries to the same action. They reuse the dark theme, native focus/scrolling, Cancel, Escape and close behavior. Only TextEdit styles were added to the existing theme; camera, board, viewport layout and cube assets were not redesigned.
- README files, unit/repository tests and native/SQL fixtures document and verify the new flow. The test runner accepts separate Save/Open phases for slow VMs.

## Confirmed contracts and compatibility

The actual editor/wire document is **`{schemaVersion: 1, configuration: {...}}`**, not the issue's flattened illustration. Required fields are `projectId`, `bucketName`, `location`. Supported locations are exactly `europe-west9`, `us-central1`, `northamerica-northeast1`. V1 fixes/materializes `STANDARD`, uniform bucket access `true`, and public access prevention `enforced`. Unknown/duplicate fields are forbidden. The backend remains authoritative; identifier validation does not establish project existence, IAM rights or bucket-name availability.

Configured creation uses **`PUT /designs/{designId}/resources/{id}` + `If-None-Match: *`**. Editing uses the same ID and **`If-Match`** revision tag. Individual aggregate GET verifies the actual ETag; aggregate list reads use `include=configuration` and the documented per-revision tag format. There is no metadata-POST-then-configuration-PUT sequence for configured creation.

New templates contain explicitly labelled illustrative identifiers for review. Legacy unconfigured resources remain visible and identified as unconfigured; their form leaves required identifiers blank and saves configuration onto the same server ID only after explicit input. Other resource kinds keep local placement. Cloud Storage requires an active Design and an empty or Cloud Storage tile; it no longer silently replaces a different local kind. The header skips confirmed configured rows and retains metadata-only Save for older unconfigured local snapshots. The legacy 2D domain interaction remains available.

## Exact committed source and environment

Final validations use implementation **`f39f076127470d78e77b7177d18250d704d1dc36`**, exported freshly to `/tmp/blacksmith-issue55-final-d6lg14nt`.

- Frontend tree: `cd9fe72dedfa977cd7d8f5f2fa20bd2784c44e40`.
- Backend tree: `b4388c1ef2a5f6cce7fc49541e932d1313f1cc30`, unchanged.
- All **256 tracked frontend/backend files** matched the commit after fresh generation. Only existing package resolution and native binaries were reused; generated parts/build caches were not copied.
- Dart **3.12.2**, Godot **4.4.stable.official.4c311cbee**, native X11/OpenGL Compatibility, Mesa llvmpipe. Existing Dev Container `d26cb899e251`, .NET SDK **8.0.426**; API and test-host Release builds: **0 warnings, 0 errors**. No dependency upgrade.
- Real API: `http://172.18.0.4:5155`, isolated database `blacksmith_front_smoke_c78d701130ec45a6958d77d086765cf7`, all six existing migrations verified. Test API used an unusable GCP credential path. The API is now stopped and the disposable database removed; existing Docker containers and volumes remain.

The report/screenshots follow-up commit preserves these tested frontend/backend trees.

## Actual results

| Check | Result |
| --- | --- |
| Fresh bindings | **PASS** — 57 outputs, 193 actions; generation succeeded. |
| Dart analysis and tests | **PASS** — no issues; **192 tests**. Includes JSON syntax/required fields/duplicates/unsupported fields, modal target isolation, cancellations, double submit, rejection, stale revision, lost-response/read-only recovery, missing-row uncertainty and complete-save accounting. |
| Real HTTP/PostgreSQL integration | **PASS** — rejected configured create leaves no row; rejected edit preserves metadata/configuration/revision; stable-UUID recovery, conditional create/update, duplicate/stale `412`, occupied-tile `409`, no-op revision stability, multiple resources and unrelated-Design isolation. |
| Native configured Save / Quit / Open | **PASS** — both palette entries, real backend field rejection, delayed successful response, lost committed response, same-UUID recovery, edit/no-op, full process restart, both restored JSON documents, repeated Open and scene reload. |
| Native modal at 960 × 640 | **PASS** — usable editor bounds, long-JSON scrolling, focus, Escape and close without writes; error text/input retained; no provisional cube. |
| Workspace interactions / scene round trips | **PASS** — two scene-save cycles retain viewport/camera, desktop layouts through 1920 × 1080, actual native clamp to 960 × 640, perimeter cube bounds, local interactions, node reuse and shared-BLoC disposal. Offline geometry checks explicitly seed legacy Cloud Storage projections after checking dialog cancellation; configured saves are verified by the separate real-API journey. |
| Clean default 3D / legacy 2D launches | **PASS**, repeated workspace command exit zero — normal production bootstrap, empty state, zero outgoing IP connections. All scene-save, interaction and clean-launch stages passed on the recheck. The earlier session anomaly is recorded below. |
| Native New Design dialog | **PASS**, command exit zero — validation, cancellation, controlled error, duplicate-submit guard, discard only after success, active Design and scene reload; no cloud calls. |
| Legacy 2D interaction/DI/local-fallback checks | **PASS**, command exit zero — selection, placement/replacement/reuse, reload and zero repository/HTTP calls in shared-DI and deliberately unavailable-DI modes. Fresh headless import emitted the eight Godot errors described below; it was not an error-free import. |
| Independent SQL | **PASS** — exactly two Resources and two v1 configurations in the native Design; original IDs/coordinates and revisions verified before cleanup. |
| Network/provisioning | **PASS** — persistence runtime connections only to the dedicated API; workspace, New Design and clean launches had zero outgoing IP connections. Legacy tracing saw only the local import debugger connection on port 6222. Cloud tripwires: `cloud_calls=0`, `cloud_http=0`. |
| Development DB / cleanup | **PASS** — its migration list and Design/Resource/catalog fingerprints exactly match the pre-test snapshot. Both owned temporary databases were removed. No stashes were applied/deleted; no unrelated work, shared history or Docker volume was removed. |

### Native persistence evidence

Design **`8964caae-93d4-42d8-9939-208c472be792`**. Save process **151087** exited; Open process **156063** restored:

| Resource ID | API x/y | Revision | Restored bucketName |
| --- | --- | --- | --- |
| `f6998484-a128-4834-ad5d-8f24c4e229dc` | 3 / 2 | 2 | `blacksmith-native-fixture-edited` |
| `807d7bf8-3c4a-43de-8a42-7fb7b1d26c97` | 1 / 4 | 1 | `blacksmith-native-second` |

The five UI PUT attempts comprise one deliberate real `400`, two creations (`201`, one response lost), one edit (`200`) and one semantic no-op (`200`). Retrying the rejection kept the original UUID. Check Save sent no write; header Save issued no redundant request. One metadata-only POST deliberately created a separate legacy fixture for compatibility inspection; it was not part of either configured creation. Open/repeated Open/reload issued **zero POSTs and zero PUTs**. Test project/bucket identifiers were explicit nonsecret fixture values, never provisioning requests.

Unedited native captures: [minimum-size JSON editor](images/issue_55/minimum_json_dialog.png), [two cubes after relaunch](images/issue_55/after_relaunch.png), [restored configuration editor](images/issue_55/restored_configuration.png).

## Reproduction and evidence

From the committed export's `frontend/src`:

```bash
/usr/lib/dart/bin/dart run build_runner build --delete-conflicting-outputs
/usr/lib/dart/bin/dart analyze
/usr/lib/dart/bin/dart test --reporter expanded
BLACKSMITH_INTEGRATION_BASE=http://172.18.0.4:5155 /usr/lib/dart/bin/dart run test_support/resource_api_integration.dart
```

Use a newly owned isolated backend from `frontend/scripts/start-design-test-backend.py` on rerun; the recorded API/database are stopped/removed. Native commands run from the export root, sequentially, using the installed native libraries:

```bash
python3 frontend/scripts/test-godot.py --persistence http://172.18.0.4:5155 --persistence-phase save --native-dir /home/dexter/Documents/isometric_map_test/blacksmith/frontend --trace-network --timeout 600 --output /tmp/blacksmith-issue55-final-persistence
python3 frontend/scripts/test-godot.py --persistence http://172.18.0.4:5155 --persistence-phase open --native-dir /home/dexter/Documents/isometric_map_test/blacksmith/frontend --trace-network --timeout 600 --output /tmp/blacksmith-issue55-final-persistence
set -o pipefail
python3 frontend/scripts/test-godot.py --application --native-dir /home/dexter/Documents/isometric_map_test/blacksmith/frontend --trace-network --timeout 600 --output /tmp/blacksmith-issue55-final-workspace-recheck | tee /tmp/blacksmith-issue55-final-workspace-recheck.log
python3 frontend/scripts/test-godot.py --design --native-dir /home/dexter/Documents/isometric_map_test/blacksmith/frontend --trace-network --timeout 600 --output /tmp/blacksmith-issue55-final-design
strace -f -qq -e trace=connect -o /tmp/blacksmith-issue55-final-legacy.network.log python3 frontend/scripts/test-godot.py --native-dir /home/dexter/Documents/isometric_map_test/blacksmith/frontend --timeout 600 --output /tmp/blacksmith-issue55-final-legacy
```

SQL verification used the owned run `/tmp/blacksmith-design-backend-do6a4sjm` and the native Design ID above before cleanup. Local logs, HTTP summaries, network traces, source comparison and DB fingerprints remain under `/tmp/blacksmith-issue55-final-*`; temporary logs may be cleared by the OS. Essential results and three screenshots are retained here.

## Observations, limits and rollout prerequisites

- Initial combined working-tree native execution ended with **143 (SIGTERM)** during Open, without a logged Dart/Godot explanation. That interrupted run is not a passing restart result. The committed Save/Open invocations above both subsequently exited zero and passed. The first workspace session also reported 143 after all native child checks and its final marker. Repeating the identical committed workspace checks with progress streamed through `tee` completed with **exit zero**; no source change was needed. The cause of the earlier session exits was not established.
- The locked generator warns that its analyzer predates Dart 3.12. Native llvmpipe cannot change VSync; isolated scenes fall back from old script UIDs to their valid text paths. Repeated mouse-enter test notifications can also warn. No engine/dependency/scene-UID change was introduced to hide these messages.
- Fresh headless editor import emitted **eight `ERROR:` lines** from `editor/progress_dialog.cpp` (progress dialog while flushing the message queue, then missing-task errors). It returned zero and reached the ready marker. Both following 2D runtime scenarios and the separate graphical 2D launch passed without native error lines. This reproduces the previously documented import anomaly; it is not presented as a clean import or proved to be a new regression.
- Recovery intent is **in memory**, not a durable crash journal. An unobserved original ID remains unknown; Check Save does not blindly resubmit it. Conflicts preserve the draft and require explicit reconciliation/Open, without automatic merging or replacement IDs. Persisted deletion/moving/kind replacement and configuration UIs for other kinds remain outside this issue.
- **Development runtime prerequisite:** `blacksmith_db` still has four migrations and no configuration table. Apply existing `20261025205111_AddResourceConfigurations` and `20261026040000_EnforceResourceIdentityAndOccupancy` deliberately through the normal backend workflow before using Save/Open against it. Tests did not apply migrations there.
- Save validates and stores configuration only. No `/cloud_services` call, cloud preflight, provisioning, credentials UI, deployment status icons or real bucket creation was added. Explicit Save & Deploy, authorization, tracked cloud outcomes and live GCP tests remain the next separately scoped increment. No automatic merge.
