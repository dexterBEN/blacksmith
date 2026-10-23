extends SceneTree
## Rasterize unmodified official SVG sources at a usable texture resolution.
## No color, shape or aspect-ratio adaptation is applied.


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 1:
		push_error("Expected the absolute resource_cubes/icons directory.")
		quit(1)
		return
	var directory: String = arguments[0]
	DirAccess.make_dir_recursive_absolute(directory.path_join("rendered"))
	for service in ["cloud_storage", "cloud_vpn", "cloud_load_balancing"]:
		var svg := FileAccess.get_file_as_string(directory.path_join("official/%s.svg" % service))
		var image := Image.new()
		if image.load_svg_from_string(svg, 256.0 / 24.0) != OK:
			push_error("Could not rasterize official icon: " + service)
			quit(1)
			return
		assert(image.get_size() == Vector2i(256, 256))
		if image.save_png(directory.path_join("rendered/%s.png" % service)) != OK:
			push_error("Could not save rendered icon: " + service)
			quit(1)
			return
	print("BLACKSMITH_OFFICIAL_ICONS_RENDERED icons=3 size=256 colors=unchanged")
	quit()
