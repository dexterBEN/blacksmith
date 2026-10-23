extends SceneTree
## Author one shared beveled cube, preserving the original six-face UV atlas.
## All coordinates are centered while authoring, then lifted to a Y=0 base.

const HALF := Vector3(0.5, 0.5, 0.5)
const BEVEL := 0.045
var surface := SurfaceTool.new()


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 1:
		push_error("Expected an absolute output path for the shared cube mesh.")
		quit(1)
		return
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inset := HALF - Vector3.ONE * BEVEL
	for axis in range(3):
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3
		for sign_value in [-1, 1]:
			var corners: Array[Vector3] = []
			for pair in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var point := Vector3.ZERO
				point[axis] = sign_value * HALF[axis]
				point[u] = pair.x * inset[u]
				point[v] = pair.y * inset[v]
				corners.append(point)
			quad(corners[0], corners[1], corners[2], corners[3])
		for sign_u in [-1, 1]:
			for sign_v in [-1, 1]:
				var corners: Array[Vector3] = []
				for side in [-1, 1]:
					var point := Vector3.ZERO
					point[axis] = side * inset[axis]
					point[u] = sign_u * HALF[u]
					point[v] = sign_v * inset[v]
					var other := point
					other[u] = sign_u * inset[u]
					other[v] = sign_v * HALF[v]
					corners.append(point)
					corners.append(other)
				quad(corners[0], corners[2], corners[3], corners[1])
	for x in [-1, 1]:
		for y in [-1, 1]:
			for z in [-1, 1]:
				var point := Vector3(x, y, z) * inset
				var a := point
				var b := point
				var c := point
				a.x = x * HALF.x
				b.y = y * HALF.y
				c.z = z * HALF.z
				triangle(a, b, c)
	surface.index()
	var mesh := surface.commit()
	mesh.resource_name = "ResourceCube_1x1x1_Bevel0.045"
	assert(mesh.get_aabb().position.is_equal_approx(Vector3(-0.5, 0, -0.5)))
	assert(mesh.get_aabb().size.is_equal_approx(Vector3.ONE))
	assert(mesh.surface_get_array_index_len(0) == 44 * 3)
	if ResourceSaver.save(mesh, arguments[0]) != OK:
		push_error("Could not save the shared cube mesh.")
		quit(1)
		return
	print("BLACKSMITH_RESOURCE_CUBE_GENERATED triangles=44 bevel=0.045 base_y=0")
	quit()


func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	triangle(a, b, c)
	triangle(a, c, d)


func triangle(a: Vector3, b: Vector3, c: Vector3) -> void:
	var normal := (b - a).cross(c - a).normalized()
	if normal.dot(a + b + c) < 0:
		var temporary := b
		b = c
		c = temporary
		normal = -normal
	var inset := HALF - Vector3.ONE * BEVEL
	# Godot front faces are clockwise; smooth normals round only the bevels.
	for vertex in [a, c, b]:
		surface.set_normal((vertex - vertex.clamp(-inset, inset)).normalized())
		surface.set_uv(atlas_uv(vertex, normal))
		surface.add_vertex(vertex + Vector3(0, 0.5, 0))


func atlas_uv(vertex: Vector3, normal: Vector3) -> Vector2:
	var axis := normal.abs().max_axis_index()
	var uv: Vector2
	if axis == Vector3.AXIS_Z and normal.z > 0:
		uv = Vector2(0.25 + (vertex.x + 0.5) * 0.25, 0.5 + vertex.y / 3.0)
	elif axis == Vector3.AXIS_X and normal.x > 0:
		uv = Vector2(0.5 + (0.5 - vertex.z) * 0.25, 0.5 + vertex.y / 3.0)
	elif axis == Vector3.AXIS_Z:
		uv = Vector2(0.75 + (0.5 - vertex.x) * 0.25, 0.5 + vertex.y / 3.0)
	elif axis == Vector3.AXIS_X:
		uv = Vector2((vertex.z + 0.5) * 0.25, 0.5 + vertex.y / 3.0)
	elif normal.y > 0:
		uv = Vector2(0.25 + (vertex.x + 0.5) * 0.25, 5.0 / 6.0 - vertex.z / 3.0)
	else:
		uv = Vector2(0.25 + (vertex.x + 0.5) * 0.25, (vertex.z + 0.5) / 3.0)
	# OBJ V points up; Godot's image UVs point down.
	return Vector2(uv.x, 1.0 - uv.y)
