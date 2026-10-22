extends SceneTree
## Compare an old/new mesh in a temporary native Godot project (no Dart needed).
## Arguments: baseline .tres, updated .tres, output .json; all absolute paths.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not require(args.size() == 3, "Expected baseline, updated and output paths"):
		return
	var baseline := load(args[0]) as ArrayMesh
	var updated := load(args[1]) as ArrayMesh
	if not require(baseline != null and updated != null, "Both meshes must load"):
		return
	if not require(baseline.get_surface_count() == 3 and updated.get_surface_count() == 3,
			"Expected three surfaces"):
		return
	if not require(baseline.get_aabb().is_equal_approx(updated.get_aabb()), "AABB changed"):
		return
	var result := {
		"triangles": 44, "surfaces": 3,
		"positions_and_winding_unchanged": true, "only_bevel_normals_changed": true,
		"vertices_before": [], "vertices_after": [],
	}
	for surface in 3:
		var old := baseline.surface_get_arrays(surface)
		var current := updated.surface_get_arrays(surface)
		if not require(triangles(old) == triangles(current), "Triangle positions/winding changed"):
			return
		if not require(updated.surface_get_array_index_len(surface) == [6, 96, 30][surface],
				"Triangle count changed"):
			return
		result.vertices_before.append(baseline.surface_get_array_len(surface))
		result.vertices_after.append(updated.surface_get_array_len(surface))
		for index in current[Mesh.ARRAY_VERTEX].size():
			var vertex: Vector3 = current[Mesh.ARRAY_VERTEX][index]
			var normal: Vector3 = current[Mesh.ARRAY_NORMAL][index]
			if not require(normal.is_finite() and abs(normal.length() - 1) < 0.002
					and normal.dot(vertex) > 0, "Normals must be finite, unit and outward"):
				return
		if surface != 1:
			if not require(old[Mesh.ARRAY_VERTEX] == current[Mesh.ARRAY_VERTEX]
					and old[Mesh.ARRAY_NORMAL] == current[Mesh.ARRAY_NORMAL],
					"Top/side vertices and normals changed"):
				return
	var file := FileAccess.open(args[2], FileAccess.WRITE)
	if not require(file != null, "Could not write verification result"):
		return
	file.store_string(JSON.stringify(result, "  "))
	file.close()
	print("BLACKSMITH_ISSUE25_MESH_VERIFIED ", JSON.stringify(result))
	quit()

func require(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition

func triangles(arrays: Array) -> Array:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var result := []
	for index in range(0, indices.size(), 3):
		var points := []
		for corner in 3:
			var vertex := vertices[indices[index + corner]]
			points.append("%.6f,%.6f,%.6f" % [vertex.x, vertex.y, vertex.z])
		# Cyclic rotations preserve winding; reversed orders deliberately differ.
		var rotations := [points[0] + "/" + points[1] + "/" + points[2],
			points[1] + "/" + points[2] + "/" + points[0],
			points[2] + "/" + points[0] + "/" + points[1]]
		rotations.sort()
		result.append(rotations[0])
	result.sort()
	return result
