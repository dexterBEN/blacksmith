extends Node3D
## Static visual children of the existing Dart grid; no input or BLoC ownership.

const Preview := preload("res://tools/resource_cubes_preview.gd")


func _ready() -> void:
	for index in Preview.SERVICES.size():
		var service: String = Preview.SERVICES[index]
		var packed: PackedScene = load("res://assets/models/resource_cubes/%s.tscn" % service)
		var model: Node3D = packed.instantiate()
		var cell: Vector2i = Preview.CELLS[index]
		model.name = service
		model.position = Vector3((cell.y - 2.5) * Preview.PITCH, Preview.TOP, (cell.x - 2.5) * Preview.PITCH)
		model.scale = Vector3.ONE * Preview.MODEL_SCALE
		add_child(model)
	assert(get_child_count() == 4)
	print("BLACKSMITH_RESOURCE_CUBES_DEMO_READY models=4 input_handlers=0")
