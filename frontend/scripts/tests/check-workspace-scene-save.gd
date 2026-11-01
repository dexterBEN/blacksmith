@tool
extends SceneTree

# Run only inside test-godot.py's disposable project. Saving the parent scene
# used to silently discard children added inside a non-editable scene instance.
const WORKSPACE = "res://scenes/isometric_3d/workspace_controls.tscn"
const SCENE = "res://scenes/isometric_3d.tscn"
const CANVAS = "Body/Center/Canvas"
const DIAL = "Body/Center/SpeedDial"

func _initialize():
	for cycle in range(2):
		for path in [WORKSPACE, SCENE]:
			var packed = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
			var scene = packed.instantiate(PackedScene.GEN_EDIT_STATE_MAIN)
			var prefix = "" if path == WORKSPACE else "WorkspaceLayer/Workspace/"
			var viewport = scene.get_node_or_null(prefix + CANVAS + "/WorldViewport")
			if not viewport is SubViewport or not viewport.get_node_or_null("Camera3D") is Camera3D:
				push_error("Workspace viewport/camera missing after editor save: " + path)
				scene.free()
				quit(1)
				return
			var dial = scene.get_node_or_null(prefix + DIAL)
			if not dial is Control or not is_equal_approx(dial.offset_left, 18.0) or not is_equal_approx(dial.offset_bottom, -18.0):
				push_error("Speed Dial margins changed after editor save: " + path)
				scene.free()
				quit(1)
				return
			var welcome = scene.get_node_or_null(prefix + "EmptyState")
			var invalid_defaults = dial.visible or not welcome is Control or not welcome.visible
			if path == SCENE:
				invalid_defaults = invalid_defaults or scene.get_node("GridRoot").visible or scene.get_node("ResourceRoot").visible
			if invalid_defaults:
				push_error("Empty workspace defaults changed after editor save: " + path)
				scene.free()
				quit(1)
				return
			var saved = PackedScene.new()
			var result = saved.pack(scene)
			if result == OK:
				result = ResourceSaver.save(saved, path)
			scene.free()
			if result != OK:
				push_error("Could not save workspace regression fixture: " + path)
				quit(1)
				return
	print("BLACKSMITH_WORKSPACE_SCENE_SAVE_PASSED cycles=2 viewport=true camera=true dial_margins=true empty_defaults=true")
	quit()
