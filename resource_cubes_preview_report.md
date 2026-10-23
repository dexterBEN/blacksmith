# Issue #28 / PR #29 — GCP resource cube assets

[Issue #28](https://github.com/dexterBEN/blacksmith/issues/28) ·
[PR #29](https://github.com/dexterBEN/blacksmith/pull/29) · branch `issue_28`.

Four reusable Godot scenes display Cloud Storage, Compute Engine, Cloud VPN
and Load Balancing on the existing 3D board. The final visual assets restore
commit `5d26367`, including its white service icons, at the user's explicit
request. The missing Storage and VPN texture fixes are retained, so the scenes
can load from committed sources rather than relying on local files.

## Changes and cleanup

- Restore the three white SVGs and their material references byte-for-byte from
  `5d26367`. The four scene wrappers, shared mesh, shader and all four materials
  also match that baseline. Compute Engine keeps its supplied-pack CPU symbol.
- Preserve all four original atlas PNGs. Storage and VPN were absent from
  `5d26367`; both were recovered from the supplied ZIP. All four PNGs match
  that ZIP byte-for-byte and are required by the native materials.
- Remove the eight original OBJ/MTL comparison files and their pack README.
  The reusable scenes use the shared native mesh, not those source meshes.
- Remove the three colored icon PNGs and their now-unused rasterization tool.
  Godot imports the selected 256-pixel white SVGs directly.
- Remove eight redundant committed comparison/full-board evidence files and
  clean up the historical untracked comparison outputs. Before/after evidence
  is already recorded in the PR. Keep two useful captures and two JSON records.
- Remove the resource preview's `--compare`, `--variant` and `--generate-icons`
  options and associated branches. Update dependency checks and documentation
  to match the retained files.

The PR now contains **35 changed files instead of 53** against `master`:
17 runtime assets, three original SVG sources for provenance, seven launcher /
validation / authoring files, four documentation / provenance files and four
validation evidence files. No native libraries or new import caches are included.

The original ZIP and earlier Git commits retain the comparison meshes. The
four `source/*/*_texture.png` files stay in the repository because they remain
runtime dependencies. The original Google SVGs stay as provenance sources;
they are distinct from the white derivatives used at runtime.

## Asset conventions and demonstration

The shared mesh is **1 × 1 × 1**, Y-up, centered on X/Z=0 with its base at Y=0.
It has a **0.045-unit chamfer** and **44 triangles**. All four scene wrappers
reuse this mesh. The opaque shader uses metallic=0, roughness=0.38,
specular=0.25 and clearcoat=0.18, with the original atlas orientation preserved.

The demonstration uses uniform scale **0.68** and base height **Y=0.12**, inside
the existing tile's 0.93-unit flat top. Cells `(row, column)` are Storage `(3,1)`,
Compute `(1,2)`, VPN `(2,4)` and Load Balancing `(4,3)`.

The asset-only preview needs Python, Godot 4.4 and X11. It builds an empty
temporary project from the existing board, camera, lighting and backdrop, then
uses a native visual fixture. It needs no Dart libraries, package caches,
previous imports or backend. Final publication validation uses a clean export
of the exact commit and a fresh import.

The opt-in `--resource-cubes` mode in the existing Dart-grid launcher adds four
static visual children in a temporary scene. The existing Dart grid, real BLoC,
tile picking, highlighting and lifecycle tests stay active. Its fake repository
and HTTP client reject unexpected calls. This is a visual demonstration, not
application resource placement or provisioning.

## Validation

| Check | Result |
| --- | --- |
| Visual baseline | All 13 scene/mesh/shader/material/white-SVG files match `5d26367` |
| Texture integrity | All four atlases match the supplied ZIP |
| Dependency closure | 20 resource/provenance files; missing Storage or VPN PNG is rejected |
| Git-index inclusion | Required dependencies must be tracked before publication |
| Fresh native asset import and rendering | Passed: four models, 36 tiles, geometry/material assertions |
| Dart unit tests | 49 passed |
| Dart static analysis | No issues found |
| Native Dart 3D selection/lifecycle with cubes | Passed; 36 centers, zero repository/HTTP calls |

The 3D regression covers all 36 tile centers, gaps/outside clicks, GUI
interception, resizing, external state updates, scene reloads, subscription
counts and fallback disposal. It asserts zero repository/HTTP calls and checks
that all four visual cubes survive reloads. Results and dependency hashes are
recorded in [publication_validation.json](docs/frontend/resource_cubes_preview/publication_validation.json).

The existing native 2D scene and local diagnostic passed during the preceding
PR validation; they are unchanged by this cleanup and were not rerun. Their
headless editor import has known Godot 4.4 progress-dialog diagnostics on this
VM. The new asset checks use the windowed editor instead. The final native
asset and 3D import/runtime logs have no engine, script or shader errors or
ObjectDB leak warnings; the existing 3D UID warning falls back to its text path. Captures and runtime
measurements use VirtualBox/Mesa llvmpipe software rendering; they are local
validation evidence, not CI results or a hardware-performance claim.

## Current captures

![Four resource cubes with active tile selection](docs/frontend/resource_cubes_preview/active_selection/selection_edge.png)

![Compute and Storage icon detail](docs/frontend/resource_cubes_preview/active_selection/resource_cubes_two_services.png)

[Runtime sample](docs/frontend/resource_cubes_preview/active_selection/runtime.json).

## Reproduce

From the repository root:

```bash
python3 frontend/scripts/check_resource_cubes.py --require-tracked
python3 frontend/scripts/preview-resource-cubes.py --check --output /tmp/blacksmith-assets
python3 frontend/scripts/run-isometric-3d.py --resource-cubes --check --timeout 600 --output /tmp/blacksmith-selection
```

Run `dart test` and `dart analyze` from `frontend/src`. The Dart-grid launcher
requires the existing local native libraries, generated bindings and package
configuration. These development prerequisites are not committed asset imports.
The asset-only launcher imports through X11 even when its scene check uses
`--headless`; see the [asset README](frontend/assets/models/resource_cubes/README.md).

## Observations and remaining limits

The selected white icons are **modified derivatives**, not unmodified or
Google-approved official artwork. Original sources, attribution and hashes are
retained in the [icon usage notes](frontend/assets/models/resource_cubes/icons/README.md)
and [provenance](frontend/assets/models/resource_cubes/icons/provenance.json).
No separate permission for recoloring has been established; the user's visual
choice does not resolve that distribution question.

Cube picking, placement/removal driven by application resource state,
persistence and provisioning remain separate work. The reflection probe
captures lighting cards rather than reflections of the cubes.

No production BLoC, placement logic, main scene, backend, database, provisioning
or Dev Container changes are included. All existing Git stashes are preserved.
Publication adds a normal commit to `issue_28`; no history rewrite or automatic
PR merge is involved.
