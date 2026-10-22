extends SceneTree
## Author the shared native mesh once; no geometry generation occurs at runtime.
## Run from a temporary Godot project without the Dart extension (see report).

const HALF := Vector3(0.5, 0.12, 0.5)
const BEVEL := 0.035
const TOP := 0
const BEVELS := 1
const SIDES := 2
var surfaces: Array[SurfaceTool] = []

func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 1:
		push_error("Expected one absolute output path for beveled_tile.tres")
		quit(1)
		return
	for material_path in ["tile_material.tres", "bevel_material.tres", "side_material.tres"]:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		surface.set_material(load("res://scenes/isometric_3d/" + material_path))
		surfaces.append(surface)
	var inset := HALF - Vector3.ONE * BEVEL
	for axis in range(3):
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3
		# Six flat face centers.
		for sign_value in [-1, 1]:
			var corners: Array[Vector3] = []
			for pair in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var p := Vector3.ZERO
				p[axis] = sign_value * HALF[axis]
				p[u] = pair.x * inset[u]
				p[v] = pair.y * inset[v]
				corners.append(p)
			quad(corners[0], corners[1], corners[2], corners[3], TOP if axis == 1 and sign_value == 1 else SIDES)
		# Twelve sloping edge strips, including the bottom and vertical edges.
		for sign_u in [-1, 1]:
			for sign_v in [-1, 1]:
				var corners: Array[Vector3] = []
				for side in [-1, 1]:
					var p := Vector3.ZERO
					p[axis] = side * inset[axis]
					p[u] = sign_u * HALF[u]
					p[v] = sign_v * inset[v]
					var q := p
					q[u] = sign_u * inset[u]
					q[v] = sign_v * HALF[v]
					corners.append(p)
					corners.append(q)
				quad(corners[0], corners[2], corners[3], corners[1], BEVELS)
	# Eight triangular corner caps close the mesh.
	for x in [-1, 1]:
		for y in [-1, 1]:
			for z in [-1, 1]:
				var p := Vector3(x, y, z) * inset
				var a := p
				var b := p
				var c := p
				a.x = x * HALF.x
				b.y = y * HALF.y
				c.z = z * HALF.z
				triangle(a, b, c, BEVELS)
	var mesh := ArrayMesh.new()
	for index in surfaces.size():
		surfaces[index].index()
		surfaces[index].commit(mesh)
		mesh.surface_set_name(index, ["Top", "Bevels", "SidesAndBottom"][index])
	mesh.resource_name = "BeveledTile_1x0.24x1_Bevel0.035"
	var error := ResourceSaver.save(mesh, arguments[0])
	if error != OK:
		push_error("Could not save tile mesh: %s" % error)
		quit(1)
		return
	print("BLACKSMITH_TILE_MESH_SAVED triangles=44 surfaces=3 indices=", mesh.surface_get_array_index_len(0) + mesh.surface_get_array_index_len(1) + mesh.surface_get_array_index_len(2))
	quit()

func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, surface_index: int) -> void:
	triangle(a, b, c, surface_index)
	triangle(a, c, d, surface_index)

func triangle(a: Vector3, b: Vector3, c: Vector3, surface_index: int) -> void:
	var normal := (b - a).cross(c - a).normalized()
	# Outward normals, clockwise front faces as required by Godot.
	if normal.dot(a + b + c) < 0:
		var temporary := b
		b = c
		c = temporary
		normal = -normal
	var surface := surfaces[surface_index]
	for vertex in [a, c, b]:
		# Interpolate a rounded-box normal only across the existing chamfers.
		# Top/side normals, positions, winding and triangle count stay intact.
		var shading_normal := normal
		if surface_index == BEVELS:
			var inset := HALF - Vector3.ONE * BEVEL
			shading_normal = (vertex - vertex.clamp(-inset, inset)).normalized()
		surface.set_normal(shading_normal)
		surface.add_vertex(vertex)
