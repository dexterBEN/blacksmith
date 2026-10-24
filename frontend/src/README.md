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

Both commands use the production bootstrap. There is no dependency on
`test_support/`, a test launcher, a test environment variable, backend services,
database access or GCP credentials for local placement. Native libraries and
package caches remain development prerequisites and are not committed.

The current locked generator may warn that its analyzer predates Dart 3.12.
Generation is verified with the installed versions; do not upgrade dependencies
just to suppress that warning. See the root issue report for executed checks.
