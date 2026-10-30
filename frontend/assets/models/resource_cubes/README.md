# Resource cube assets

Four reusable visual scenes for Cloud Storage, Compute Engine, Cloud VPN and
Load Balancer, derived from the supplied `Blacksmith_Godot_3D_Models.zip`.
Instancing a scene does not create a cloud resource or update application state.

## Required files

- Four `.tscn` wrappers share `beveled_resource_cube.tres` and the opaque
  `coated_blue_plastic.gdshader`, with one material per service in `materials/`.
- `source/*/*_texture.png` contains the four unchanged supplied-pack atlases.
  All four are runtime dependencies, including the restored Storage and VPN PNGs.
- `icons/white/` contains the three 256-pixel white SVG adaptations restored
  byte-for-byte from commit `5d26367`, as explicitly requested during PR review.
- `icons/official/` preserves their original Google SVG sources for provenance.
  See [icon usage notes](icons/README.md) and [hashes](icons/provenance.json).

Original OBJ/MTL comparison files, colored icon rasterizations and duplicate
before/after captures have been removed. Use the native `.tscn` wrappers; no
Blender conversion is required. The source ZIP and previous commits retain the
original comparison meshes.

## Geometry and placement

Each cube is **1 × 1 × 1**, Y-up, centered on X/Z=0 with its base at Y=0.
The shared mesh has a **0.045** chamfer and **44 triangles**. Its face atlas
orientation is preserved. Compute Engine retains the supplied-pack CPU symbol;
the other three front faces use the white adaptations. Icons are flat artwork.

For an existing unscaled tile (1 × 0.24 × 1), add the resource scene as a child,
set its local position to `(0, 0.12, 0)` and its uniform scale to `0.68`.
Its base contacts the tile top and its footprint fits inside the 0.93-unit flat
surface. The reusable asset itself remains unscaled.

The shader uses metallic=0, roughness=0.38, specular=0.25 and clearcoat=0.18.
Its `(0.42, 0.58, 0.9)` blue-pigment multiplier preserves white glyphs. For the
three replacement icons, the shader rebuilds the front's blue gradient from
clean atlas margins and samples `service_icon` with `icon_scale=0.7`.
This calibration is specific to these supplied atlases.

## Preview and validation

Run from the repository root with Python 3 and Godot 4.4:

```bash
# Check all 20 resource/provenance dependencies and Git-index inclusion.
python3 frontend/scripts/check_resource_cubes.py --require-tracked

# Open a standalone native preview; close its window to exit.
python3 frontend/scripts/preview/preview-resource-cubes.py

# Fresh import, geometry/material validation and actual viewport captures.
python3 frontend/scripts/preview/preview-resource-cubes.py --check --output /tmp/blacksmith-cubes

# Regenerate the shared mesh and check geometry without rendering the scene.
python3 frontend/scripts/preview/preview-resource-cubes.py --generate-mesh --headless

# Open the interactive Dart grid: select a tile, then choose a local resource.
python3 frontend/scripts/preview/run-isometric-3d.py

# Exercise actual palette input, placement/replacement, replay and lifecycle.
python3 frontend/scripts/preview/run-isometric-3d.py --check --timeout 600 --output /tmp/blacksmith-placement
```

The asset-only launcher creates a fresh temporary Godot project containing
committed assets and the existing board/camera/lighting/background. It replaces
only the root script in that temporary fixture. It needs no Dart native libraries,
package cache, imported resources or backend. Actual captures are 1152 × 648,
with 4× MSAA. The import uses the windowed editor to avoid Godot 4.4 headless
editor diagnostics on this VM; **X11 is required even with `--headless`**, which
applies only to the scene check. Images, JSON and logs go to the selected output.

The Dart launcher requires the usual local Godot/Dart libraries, packages and
generated bindings. Its four-choice palette places and replaces cubes from the
existing BLoC's in-memory tile state. It starts empty, with placement disabled
until a tile is selected. `--resource-cubes` remains a compatibility alias; it no
longer inserts static cubes. The asset-only preview above retains its isolated
four-cube fixture, with the interactive palette hidden.

Neither launcher needs a backend or credentials, persists placements, or calls
cloud services. The tile-plane selection algorithm is unchanged; cubes have no
separate picking handlers. Do not commit import caches, native libraries or
package caches.
