# Blacksmith Godot 3D Resource Cube Kit

This package contains **four simple 3D cube assets** intended for Godot import.

Included services:
- Cloud Storage
- Compute Engine
- Cloud VPN
- Load Balancer

## Format
Each service folder contains:
- `SERVICE.obj` — 3D mesh
- `SERVICE.mtl` — material definition
- `SERVICE_texture.png` — texture atlas used by the mesh

Godot can import `.obj` files directly. When imported, the corresponding `.mtl` and texture should be detected automatically if they remain in the same folder.

## Coordinate / scale
- Unit size: approximately **1x1x1**
- Origin: centered on the base footprint, with the bottom on **Y = 0**
- Up axis: **Y up**

## Suggested Godot usage
1. Copy one or more service folders into your project, for example under `res://src/assets/3d/`.
2. In Godot, select the `.obj` file and let the importer create the scene.
3. Instantiate the imported scene on the tile.
4. Scale the cube as needed to match your tile size.

## Notes
- These are **simple stylized 3D assets** meant to match the Blacksmith visual direction.
- The service symbols are clean semantic icons suitable for prototyping inside the app.
- If you later need stricter brand fidelity, you can replace the front-face icon texture while keeping the same mesh.
