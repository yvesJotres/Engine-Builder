extends SceneTree

# Visual check, needs a window: shows the main menu for a few seconds and saves a screenshot to the temp folder.
# Run: godot --path . -s tools/diagnostics/launcher_check.gd

const FRAMES := 180


func _init() -> void:
	await process_frame # autoloads such as Patcher are registered after _init
	var menu: Node = load("res://scenes/launcher.tscn").instantiate()
	root.add_child(menu)
	for i in FRAMES:
		await process_frame
	var path := OS.get_environment("TEMP").replace("\\", "/") + "/launcher_check.png"
	root.get_texture().get_image().save_png(path)
	print("saved %s" % path)
	quit()
