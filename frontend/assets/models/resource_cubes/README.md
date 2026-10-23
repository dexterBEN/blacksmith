# Resource cube assets

Four reusable Godot scenes derived from the user-supplied
`Blacksmith_Godot_3D_Models.zip`: Cloud Storage, Compute Engine, Cloud VPN and
Load Balancer. These are visual assets; instancing one does not create a cloud
resource or connect it to application state.

## Files and preservation

- `source/` contains the original OBJ, MTL and PNG files, byte-for-byte copies
  from the ZIP, plus its original README. Leave these unchanged for comparison.
- `beveled_resource_cube.tres` is one shared native Godot `ArrayMesh`.
- `materials/` contains one opaque coated-plastic material per original atlas.
- `coated_blue_plastic.gdshader` supplies nonmetallic lighting and calibrates
  blue pigment separately from the white icons. The original PNGs are unchanged.
- `icons/official/` contains the unmodified GCP SVGs for Cloud Storage, Cloud VPN
  and Cloud Load Balancing. See the provenance and usage notes in `icons/`.
- `icons/rendered/` contains Godot's 256-pixel rasterizations of those exact
  SVGs for crisp sampling on the cube; original colors and shapes are retained.
- The four `.tscn` files share the mesh and assign their corresponding material.

The source README describes OBJ files as imported scenes. Godot's default OBJ
import is a mesh, not a `PackedScene`; use the supplied `.tscn` wrappers instead.
No Blender installation or model conversion tool is required to use these scenes.

## Geometry and placement

The mesh is 1 × 1 × 1 units, Y-up, with its base at Y=0 and its footprint
centered on X/Z=0. A 0.045-unit chamfer replaces the sharp edges. The mesh has
44 triangles and smooth shading across the chamfers, while the six flat face
centers retain their axis-aligned normals. The face atlas orientation is preserved.
Compute Engine keeps its original supplied-pack symbol (not claimed as official).
The other three front symbols use Google's original legacy console SVGs, without
recoloring or geometry changes. Their original colors replace the earlier white
adaptations, following the user's choice during the PR #29 review.
The icons remain flat artwork, not raised geometry.

For the current unscaled tiles (1 × 0.24 × 1), instantiate a resource scene as
a child of its tile, set its position to `(0, 0.12, 0)`, and its uniform scale
to `0.68`. This leaves a visible margin inside the tile's flat top and puts
the cube base exactly on its surface. The asset itself remains unscaled for reuse.

The application selection currently intersects a ray with the tile plane. This
preview does not add picking for cubes, application placement events, persistence,
or BLoC integration.

## Preview and reproduce

From the repository root, using the existing Godot 4.4 executable:

```bash
# Open the corrected models on the current board; close the window to exit.
python3 frontend/scripts/preview-resource-cubes.py

# Check dependencies and verify they are present in the Git index.
python3 frontend/scripts/check_resource_cubes.py --require-tracked

# Capture corrected/original models with identical framing and lighting.
python3 frontend/scripts/preview-resource-cubes.py --check --compare --output /tmp/blacksmith-cubes

# Reproduce the committed high-resolution textures from unchanged official SVGs.
python3 frontend/scripts/preview-resource-cubes.py --generate-icons --check --output /tmp/blacksmith-cubes

# Use the real existing Dart grid, picking and selection with static visual cubes.
python3 frontend/scripts/run-isometric-3d.py --resource-cubes

# Run existing native selection/lifecycle checks with the cubes present.
python3 frontend/scripts/run-isometric-3d.py --resource-cubes --check --timeout 600 --output /tmp/blacksmith-cubes-selection

# Regenerate the shared mesh, then check it in the native fixture.
python3 frontend/scripts/preview-resource-cubes.py --generate-mesh --headless --output /tmp/blacksmith-cubes-geometry
```

The launcher creates a temporary Godot project. It copies the existing board
scene, materials, backdrop and reflection setup, replacing only the Dart root
script in that temporary copy with a static native visual fixture. It never
starts the backend or loads the application dependencies. The import step uses
the windowed editor to avoid Godot 4.4 headless-editor progress-dialog errors on
the current VM. A working X11 display is required, including with `--headless`
(which applies to the scene check, not the import).

Screenshots are actual 1152 × 648 Godot viewport captures. Individual-model
close-ups are unscaled crops of the same image. The JSON records the renderer,
model placement and native geometry/material checks. Logs remain local and
are ignored by Git.

The asset-only preview requires just Godot/Python and the committed assets; it
does not copy native Dart libraries, package caches or local imported resources.
The optional Dart-grid demonstration additionally requires the normal existing
Godot/Dart native libraries and generated package configuration. It uses the
established fail-closed test dependencies, never production provisioning.

Both preview variants enable 4× MSAA in the temporary project, without changing
the application rendering settings. The corrected material uses metallic=0,
roughness=0.38, specular=0.25 and clearcoat=0.18. The blue-pigment multiplier is
`(0.42, 0.58, 0.9)`; white texture pixels keep their original color. This color
separation is tuned for the supplied atlases, not arbitrary replacement artwork.

For the three corrected symbols, `replace_front_icon` removes the old painted
glyph by reconstructing the front's blue gradient from its clean left/right
texture margins. `service_icon` supplies the rendered official icon, centered with `icon_scale=0.7`.
The source SVG colors are sampled directly, without the cube body's blue tint.
Compute Engine leaves this option disabled; its material and original atlas are
unchanged. This front-face replacement is specific to these cube atlases.

## Files needed in a clean checkout

Track the four `.tscn` wrappers, shared mesh and shader, four material `.tres`
files, three official SVGs and their rendered PNGs, all original OBJ/MTL/PNG triples, and source/usage
documentation. The source PNGs are runtime dependencies of the corrected
materials too; the original OBJ/MTL files support the comparison variant.
The checker walks all 28 resource/source dependencies, including `mtllib` and `map_Kd`.

Track the Python checker/launchers, native preview/demo scripts and Dart test
fixture changes. Do not track `.godot/`, `*.import`, Python bytecode, native
libraries or package caches. Screenshots and sanitized JSON records under
`docs/frontend/resource_cubes_preview/` are review evidence rather than imports.
