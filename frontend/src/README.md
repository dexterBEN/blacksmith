# Blacksmith Dart sources

`main.dart` is the normal Godot/Dart entry point. It registers the existing script
resolver for editor/runtime use and initializes the shared GetIt services only
during application execution. The default Godot scene is
`res://scenes/isometric_3d.tscn`; `res://main.tscn` is the explicit legacy 2D scene.

With the existing compatible Godot 4.4 / Dart / `godot_dart` native artifacts
already installed, run from this directory. Validation on this VM uses Dart
3.12.2 at `/usr/lib/dart/bin/dart`; explicitly selecting it avoids the Flutter
wrapper that otherwise appears first in this VM's `PATH`.

```bash
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

The 3D workspace uses native containers for its header, four-service GCP sidebar
and quick-placement strip. Its `SubViewportContainer` renders the existing world
inside the remaining area. Camera fitting uses that viewport's real dimensions;
main-window pointer coordinates are mapped to the canvas before ray picking.
The resource palette helper connects both sets of buttons to the same existing
placement action and derives enabled state from `IsomapGridBloc`.

**Light UI / Dark UI** changes the controls, dialog and workspace frame. Cube/tile
materials, lighting and the backdrop remain unchanged: this is UI appearance,
not full light-scene parity. The presentation preference survives scene reloads
within the application session; theme changes never recreate cubes or reset
Design/grid state. At compact widths the catalog labels wrap; short windows use
its vertical scroll area. Quick icons remain visible, with service tooltips.

`test-godot.py --application --trace-network --output OUTPUT --timeout 600`
checks both entry points, compact/wide geometry, state-preserving appearance
changes and native screenshots (`dark_empty.png`, `dark_resources.png`,
`light_resources.png`, `compact.png`). Its explicit fixture Design is local to
the test; editing/theming makes no HTTP call. Separate clean launches still use
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
They survive scene reloads but not application restarts. Resource placements are
never saved, loaded, or provisioned by this workflow.

From the repository root, with the same native prerequisites as the other tests:

```bash
# UI regression with controlled responses; no actual HTTP connections.
python3 frontend/scripts/test-godot.py --design --trace-network --timeout 600 --output /tmp/blacksmith-design-ui

# Start the unchanged API in the existing backend Dev Container against a NEW
# disposable database (existing cached dependencies/database access required).
python3 frontend/scripts/start-design-test-backend.py CONTAINER_ID --port 5139
# Keep this running; note the printed RUN_PATH and the container's reachable IP.

# Sends one real POST then GET; writes only to the dedicated database above.
python3 frontend/scripts/test-godot.py --design --design-live http://CONTAINER_IP:5139 --timeout 600 --output /tmp/blacksmith-design-live
# Use id/name from /tmp/blacksmith-design-live/design_result.json:
python3 frontend/scripts/start-design-test-backend.py CONTAINER_ID --verify RUN_PATH DESIGN_ID 'DESIGN_NAME'
# Stop only this test API and drop only its generated database, including the
# dedicated test Design. Never use this command to stop the user's normal API.
python3 frontend/scripts/start-design-test-backend.py CONTAINER_ID --stop RUN_PATH
```

The native checks invoke the unchanged production bootstrap with test-only HTTP
instrumentation. Live mode forwards the successful Design POST/GET to the actual
API; its error screenshot uses a deliberate local HTTP 503 response. Cloud calls
are forbidden in both modes. Captures come directly from Godot's viewport.

The current locked generator may warn that its analyzer predates Dart 3.12.
Generation is verified with the installed versions; do not upgrade dependencies
just to suppress that warning. See the root issue report for executed checks.
