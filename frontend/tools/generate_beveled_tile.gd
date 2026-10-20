extends SceneTree
## Author the shared native mesh once; no geometry generation occurs at runtime.
## Run from a temporary Godot project without the Dart extension (see report).

const HALF := Vector3(0.5, 0.12, 0.5)
const BEVEL := 0.035
var surface := SurfaceTool.new()

func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 1:
		push_error("Expected one absolute output path for beveled_tile.tres")
		quit(1)
		return
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
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
			quad(corners[0], corners[1], corners[2], corners[3])
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
				quad(corners[0], corners[2], corners[3], corners[1])
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
				triangle(a, b, c)
	surface.index()
	var mesh := surface.commit()
	mesh.resource_name = "BeveledTile_1x0.24x1_Bevel0.035"
	var error := ResourceSaver.save(mesh, arguments[0])
	if error != OK:
		push_error("Could not save tile mesh: %s" % error)
		quit(1)
		return
	print("BLACKSMITH_TILE_MESH_SAVED triangles=44 indices=", mesh.surface_get_array_index_len(0))
	quit()

func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	triangle(a, b, c)
	triangle(a, c, d)

func triangle(a: Vector3, b: Vector3, c: Vector3) -> void:
	var normal := (b - a).cross(c - a).normalized()
	# Outward normals, clockwise front faces as required by Godot.
	if normal.dot(a + b + c) < 0:
		var temporary := b
		b = c
		c = temporary
		normal = -normal
	surface.set_normal(normal)
	surface.add_vertex(a)
	surface.add_vertex(c)
	surface.add_vertex(b)
