extends Node3D
## Visual fixture only: the application, Dart BLoC and cloud calls are not loaded.

const SERVICES := ["cloud_storage", "compute_engine", "cloud_vpn", "load_balancer"]
const CELLS := [Vector2i(3, 1), Vector2i(1, 2), Vector2i(2, 4), Vector2i(4, 3)]
# Mirror GridLayout3D for this standalone visual fixture, never for app state.
const PITCH := 1.045
const TOP := 0.12
const MODEL_SCALE := 0.68
var samples: Array[Dictionary] = []
var shared_cube_mesh: Mesh


func _ready() -> void:
	# The production camera now belongs to the workspace SubViewport. This native
	# fixture renders the board directly, so reuse that camera in the root viewport.
	var camera: Camera3D = get_node("WorkspaceLayer/Workspace/Body/Center/Canvas/WorldViewport/Camera3D")
	camera.reparent(self)
	camera.make_current()
	$WorkspaceLayer.queue_free()
	$DesignLayer.queue_free()
	var tile_scene: PackedScene = load("res://scenes/isometric_3d/tile.tscn")
	for row in range(6):
		for col in range(6):
			var tile: MeshInstance3D = tile_scene.instantiate()
			tile.name = "Tile_%d_%d" % [row, col]
			tile.position = cell_position(Vector2i(row, col))
			$GridRoot.add_child(tile)
			assert(tile.mesh.get_aabb().size.is_equal_approx(Vector3(1, 0.24, 1)))
	var models := Node3D.new()
	models.name = "ResourceModels"
	add_child(models)
	for index in SERVICES.size():
		var service: String = SERVICES[index]
		var packed: PackedScene = load("res://assets/models/resource_cubes/%s.tscn" % service)
		var model: Node3D = packed.instantiate()
		model.name = service
		model.position = cell_position(CELLS[index]) + Vector3(0, TOP, 0)
		model.scale = Vector3.ONE * MODEL_SCALE
		models.add_child(model)
		validate_model(model, service, CELLS[index])
	get_viewport().size_changed.connect(fit_camera)
	fit_camera()
	print("BLACKSMITH_RESOURCE_CUBES_READY tiles=36 models=4")
	if OS.get_environment("BLACKSMITH_CUBES_CHECK") == "1":
		capture.call_deferred()


func cell_position(cell: Vector2i) -> Vector3:
	return Vector3((cell.y - 2.5) * PITCH, 0, (cell.x - 2.5) * PITCH)


func fit_camera() -> void:
	var size := get_viewport().get_visible_rect().size
	if size.x <= 0 or size.y <= 0:
		return
	var board_width := 6.0 + 5.0 * 0.045
	var projected_width := 2.0 * board_width / sqrt(2.0)
	var projected_height := 2.0 * board_width / sqrt(6.0) + 0.24 * sqrt(2.0 / 3.0)
	$Camera3D.set_orthogonal(max(projected_height, projected_width * size.y / size.x) * 1.12, 0.1, 50)


func validate_model(model: Node3D, service: String, cell: Vector2i) -> void:
	var instance: MeshInstance3D = model.get_node("Cube")
	var mesh := instance.mesh
	var bounds := mesh.get_aabb()
	assert(bounds.position.is_equal_approx(Vector3(-0.5, 0, -0.5)))
	assert(bounds.size.is_equal_approx(Vector3.ONE))
	assert(is_equal_approx(model.position.y + bounds.position.y * MODEL_SCALE, TOP))
	assert(MODEL_SCALE < 1.0 - 2.0 * 0.035) # Inside the tile's flat top.
	var material := instance.get_active_material(0)
	assert(material is ShaderMaterial)
	var texture: Texture2D = material.get_shader_parameter("albedo_texture")
	var roughness: float = material.get_shader_parameter("roughness")
	assert(is_equal_approx(roughness, 0.38))
	assert(is_equal_approx(material.get_shader_parameter("clearcoat"), 0.18))
	var service_icon_path := ""
	# Unset parameters return Nil here; the shader's default is false.
	var replace_icon: bool = material.get_shader_parameter("replace_front_icon") == true
	assert(replace_icon == (service != "compute_engine"))
	if replace_icon:
		var service_icon: Texture2D = material.get_shader_parameter("service_icon")
		assert(service_icon != null)
		assert(service_icon.get_size() == Vector2(256, 256))
		service_icon_path = service_icon.resource_path
		assert(service_icon_path.ends_with("/icons/white/%s.svg" % service))
	if shared_cube_mesh == null:
		shared_cube_mesh = mesh
	assert(mesh == shared_cube_mesh)
	assert(texture != null)
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var triangles := indices.size() / 3
	assert(normals.size() == vertices.size() and uvs.size() == vertices.size())
	for vertex_index in vertices.size():
		assert(is_equal_approx(normals[vertex_index].length(), 1.0))
		assert(uvs[vertex_index].x >= 0 and uvs[vertex_index].x <= 1)
		assert(uvs[vertex_index].y >= 0 and uvs[vertex_index].y <= 1)
	for triangle_index in range(0, indices.size(), 3):
		var a := vertices[indices[triangle_index]]
		var b := vertices[indices[triangle_index + 1]]
		var c := vertices[indices[triangle_index + 2]]
		assert((c - a).cross(b - a).dot((a + b + c) / 3.0 - Vector3(0, 0.5, 0)) > 0)
	assert(triangles == 44)
	samples.append({"service": service, "cell": [cell.x, cell.y], "position": [model.position.x, model.position.y, model.position.z], "scale": MODEL_SCALE, "triangles": triangles, "metallic": 0.0, "roughness": roughness, "texture": texture.resource_path, "service_icon": service_icon_path})


func capture() -> void:
	assert(get_viewport().get_camera_3d() == $Camera3D)
	var output := OS.get_environment("BLACKSMITH_CUBES_OUTPUT")
	var headless := DisplayServer.get_name() == "headless"
	if not headless:
		# Let the existing update-once reflection probe complete before capture.
		for frame in range(16):
			await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		assert(image.get_width() == 1152 and image.get_height() == 648)
		assert(image.save_png(output.path_join("resource_cubes.png")) == OK)
		assert(image.get_region(Rect2i(340, 110, 390, 240)).save_png(output.path_join("resource_cubes_two_services.png")) == OK)
	var report := {"godot": Engine.get_version_info().string, "display": DisplayServer.get_name(), "renderer": RenderingServer.get_current_rendering_method(), "gpu": RenderingServer.get_video_adapter_name(), "viewport": [1152, 648], "msaa_3d": get_viewport().msaa_3d, "tile_count": 36, "models": samples, "rendered": not headless, "checks": "bounds, flat-top fit, base contact, UVs, normals, outward winding, triangle counts, textures, shared mesh, materials"}
	var file := FileAccess.open(output.path_join("resource_cubes.json"), FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print("BLACKSMITH_RESOURCE_CUBES_PASSED rendered=%s" % (not headless))
	get_tree().quit()
