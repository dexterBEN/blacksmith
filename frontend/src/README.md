# Blacksmith Dart sources

For the supported host and DevContainer commands, see the
[development script guide](../scripts/README.md). The recommended host sequence is
`../scripts/dev.sh host-build` followed by `../scripts/dev.sh run` from this directory.

`main.dart` is the normal Godot/Dart entry point. It registers the existing script
resolver for editor/runtime use and initializes the shared GetIt services only
during application execution. The default Godot scene is
`res://scenes/isometric_3d.tscn`; `res://main.tscn` is the explicit legacy 2D scene.

With the existing compatible Godot 4.4 / Dart / `godot_dart` native artifacts
already installed, run from this directory. Validation on this VM uses Dart
3.12.2 at `/usr/lib/dart/bin/dart`; explicitly selecting it avoids the Flutter
wrapper that otherwise appears first in this VM's `PATH`.

```bash
export PUB_CACHE="${PUB_CACHE:-$PWD/../.pub-cache}"
/usr/lib/dart/bin/dart pub get
/usr/lib/dart/bin/dart run build_runner build --delete-conflicting-outputs
/usr/lib/dart/bin/dart analyze
/usr/lib/dart/bin/dart test
```

Use the locked package versions; no dependency upgrade is required. Code generation
uses the corresponding compatible Dart binary on other platforms. It
recreates `lib/app_root.g.dart`, `lib/isomap_grid.g.dart`,
`lib/menu_overlay.g.dart`, `lib/prototypes/isometric_3d/isometric_3d_grid.g.dart`
and the script resolver `godot_dart_scripts.g.dart`. The four part files are ignored
build output, not hand-written prerequisites to copy from another working tree.
The existing tracked resolver includes both editor scenes and must stay aligned
with script registrations. Regenerate after adding/changing Godot script methods.

Launch from the repository root:

```bash
godot --path frontend --editor --import
godot --path frontend
godot --path frontend res://main.tscn
```

The first command imports Godot's resources after a fresh checkout. Opening the
project in the editor performs the same import before Run Project (F5).

The 3D workspace keeps the existing compact Design header and a full-width
`SubViewportContainer` below it. A bottom-left floating Speed Dial starts collapsed
as **+**; expanding it shows **Resources** and **Inspect** in one upward stack.
Its 160 ms animation is authored in the native `AnimationPlayer` scene.

Resources reuses the four existing placement buttons, enabled from `IsomapGridBloc`.
Inspect reuses the current details/configuration controls. Their panels now float
above the canvas instead of reserving dock width. One popup is visible at a time.
Escape, outside clicks, close controls, modals and selection reset dismiss the
appropriate UI. Popup close returns focus to the main button. Selection/placement,
configuration, persistence and deployment retain their existing state owners.
The native window minimum remains 960 × 640; the map minimum is 480 × 320.

Add `--speed-dial` to `preview --check` or `preview --headless` to run only the
focused menu/placement checks, without the longer grid regression matrix.

The isolated `preview --headless` / `preview --check` regressions exercise full-width
layout, upward expansion, Resources/Inspect, Escape, outside clicks, click-through
prevention, transparent row gaps, native resizing at 1152×648 and 960×640, and the
existing selection/placement/framing/lifecycle checks. Graphical mode writes
`speed_dial_WIDTH_collapsed.png`, `_expanded.png` and `_resources.png` from the real
viewport. `test-godot.py --application` additionally exercises the production
bootstrap, disabled choices without a selection, keyboard activation, inspector
reopening and the original Cloud Storage configuration entry point with fail-closed
repositories. See [the Issue #73 report](../../issue_73_report.md).

The workspace scene owns its `WorldViewport` and `Camera3D`, so saving the parent
cannot discard children injected into a non-editable scene instance.
Its explicit fixture Design is local to
the test; the geometry regression cancels Cloud Storage dialogs and seeds legacy
local cubes directly through the BLoC. Configured Save is verified separately by
the real API persistence journey below. Other local placement makes no HTTP call.
Separate clean launches still use
the unchanged production entrypoint. The existing `--design --trace-network`
scenario checks New Design dialog behavior without a live backend.

Both commands use the production bootstrap. There is no dependency on
`test_support/`, a test launcher, a test environment variable, backend services,
database access or GCP credentials for local placement. Native libraries and
package caches remain development prerequisites and are not committed.

The 3D editor's **New Design** button uses the existing `POST /designs` API.
Set `BLACKSMITH_BACKEND_URL` before launching Godot to override
`http://localhost:5100`, for example when the backend runs at a Dev Container IP.
The API and PostgreSQL must be running for this action; no GCP credentials are
needed. Startup and local cube placement still work without a backend.

Names are trimmed and must have 1–200 UTF-16 code units, matching the backend.
If the grid contains unsaved placements, explicitly confirm clearing them after
successful creation. Cancel and failure preserve them. While the POST is pending,
the dialog cannot be cancelled and the grid/palette cannot be edited. No POST is
automatically retried: a timeout or server failure can leave an already-created
Design, so check `GET /designs` before manually submitting again.

The active ID/name live in a shared `DesignCubit`, separate from `IsomapGridBloc`.
They survive scene reloads but not application restarts. New Design only creates
the Design; explicit Save/Open handles supported resource persistence as described below.

From the repository root, with the same native prerequisites as the other tests:

```bash
# UI regression with controlled responses; no actual HTTP connections.
python3 frontend/scripts/tests/test-godot.py --design --trace-network --timeout 600 --output /tmp/blacksmith-design-ui

# Start the unchanged API in the existing backend Dev Container against a NEW
# disposable database (existing cached dependencies/database access required).
python3 frontend/scripts/fixtures/start-design-test-backend.py CONTAINER_ID --port 5139
# Keep this running; note the printed RUN_PATH and the container's reachable IP.

# Sends one real POST then GET; writes only to the dedicated database above.
python3 frontend/scripts/tests/test-godot.py --design --design-live http://CONTAINER_IP:5139 --timeout 600 --output /tmp/blacksmith-design-live
# Use id/name from /tmp/blacksmith-design-live/design_result.json:
python3 frontend/scripts/fixtures/start-design-test-backend.py CONTAINER_ID --verify RUN_PATH DESIGN_ID 'DESIGN_NAME'
# Stop only this test API and drop only its generated database, including the
# dedicated test Design. Never use this command to stop the user's normal API.
python3 frontend/scripts/fixtures/start-design-test-backend.py CONTAINER_ID --stop RUN_PATH
```

The native checks invoke the unchanged production bootstrap with test-only HTTP
instrumentation. Live mode forwards the successful Design POST/GET to the actual
API; its error screenshot uses a deliberate local HTTP 503 response. Cloud calls
are forbidden in both modes. Captures come directly from Godot's viewport.

The current locked generator may warn that its analyzer predates Dart 3.12.
Generation is verified with the installed versions; do not upgrade dependencies
just to suppress that warning. See the root issue report for executed checks.

## Explicit multi-resource persistence

The 3D header adds Save, Open-by-ID and Copy ID. DesignCubit coordinates a snapshot
of the existing grid with ResourceRepository and DesignRepository. Save supports
multiple Cloud Storage representations (`gcp.storage.bucket`, generic catalog code
`storage`), with `x = column` and `y = row`. Each immutable grid entry keeps its
local intent key, server ID, configuration, revision and ETag; `tiles` is only a
derived kind projection for the existing renderers.

Cloud Storage now requires an active Design. Selecting an empty tile and either
Cloud Storage palette entry opens one native scrollable JSON editor. Save configuration
uses a single conditional configured PUT; no new cube enters the grid before
canonical aggregate read-back. Select an existing Cloud Storage tile and choose
Cloud Storage again to edit its JSON with the same ID, coordinates and revision.
New templates clearly identify example project/bucket values for review; legacy
unconfigured records leave required identifiers empty. Only the merged v1 envelope
and three supported regions are accepted. Unknown fields, duplicate keys and
credential documents are rejected without echoing input in error messages.

The modal's single draft lives in DesignCubit, outside the renderable grid. It
captures Design/tile and stable UUID before asynchronous work. Cancel/Escape/close
preserve the grid; pending requests cannot be cancelled through the modal. A failed
Save preserves text and identity. An unknown result locks editing and exposes
read-only Check Save; closing the form retains the shared header recovery guard.
Save does not create a bucket, check GCP availability or contact Google APIs.

Header Save skips already confirmed configured rows. Its metadata-only POST remains
for legacy local unconfigured snapshots (including the unchanged 2D domain events).
Other resource kinds keep local placement; Cloud Storage requires an empty or
Cloud Storage tile and does not silently replace a different local kind. Open
restores configured and unconfigured resources after validating the entire result.

Only a matching Design/resource read-back marks a resource saved. If A succeeds
and B fails, A stays confirmed and retry targets B. Ambiguous writes expose read-only
Check Save; no automatic write retry is performed. Repeated unchanged Save/Open
does not create rows or rebuild unchanged cube nodes. Configuration-only changes
dirty the state without replacing the resource's identity.

The uncertainty guard is in memory, not a durable journal. For a lost legacy POST
response, it accepts only one new matching record absent from the preflight snapshot.
This confirms the observed state, not which client created it; concurrent identical
creates cannot be causally distinguished. Cross-process recovery of an unacknowledged
legacy create is not guaranteed. Conditional configured creates instead retain their
original client UUID. Other resource kinds remain local; persisted kind replacement
and deletion synchronization are blocked rather than silently treated as saved.
No GCP provisioning occurs. The backend's existing configuration/occupancy migrations
must be applied deliberately to the target database before using this workflow.

The existing test backend launcher creates a dedicated database from the existing
migrations and sets an unusable GCP credential path for its API process. With that
backend running, use its numeric container IP and test port:

```bash
python3 frontend/scripts/tests/test-godot.py --persistence http://CONTAINER_IP:5144 --persistence-phase save --trace-network --timeout 600 --output /tmp/blacksmith-persistence
python3 frontend/scripts/tests/test-godot.py --persistence http://CONTAINER_IP:5144 --persistence-phase open --trace-network --timeout 600 --output /tmp/blacksmith-persistence
```

Run from the repository root (unlike the Dart commands above). This native test
creates one dedicated Design, configures two Resources through the actual popup,
injects a real backend field rejection, delays a committed response to prove the
cube remains hidden, loses another committed PUT response and reconciles by reads.
It edits/no-ops the first resource, inspects a separate legacy fixture, fully exits
Godot and opens the main Design in another process. It verifies both JSON documents,
stable IDs/revisions, repeated Open, scene reload, 960 × 640 modal scrolling/Escape
and grid framing. The two commands share their output directory; run native tests
sequentially because godot_dart's optional VM debug service uses fixed ports.
Captures come from the native viewport. Network tracing permits only the dedicated
API address; test clients add cloud tripwires and fault injection around the
unchanged production bootstrap.

For configured conditional-create/update, conflict and lost-response integration
checks against the same isolated API, run from `frontend/src`:

```bash
BLACKSMITH_INTEGRATION_BASE=http://CONTAINER_IP:5144 /usr/lib/dart/bin/dart run test_support/resource_api_integration.dart
```

Its explicit fixture project/bucket values are saved only to the temporary database;
they are never passed to a cloud endpoint.

Use `start-design-test-backend.py CONTAINER --verify-resource RUN_PATH DESIGN_ID`
for independent SQL verification of the two-resource native scenario. Use the
launcher's `--stop RUN_PATH` to stop only that test API and drop only its owned
test database. It does not remove a Docker container or volume. See
`issue_55_report.md` at the repository root for actual results and evidence.
