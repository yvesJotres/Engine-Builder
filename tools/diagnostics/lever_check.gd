extends SceneTree

# Visual check, needs a window: shows the touch layout with the throttle and clutch levers part way pulled, and saves a
# screenshot to the temp folder. Run: godot --path . -s tools/diagnostics/lever_check.gd

const FRAMES := 60


func _init() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	for child in main.get_children():
		if child is TouchControls:
			child.visible = true
	for i in FRAMES:
		await process_frame
		main._touch_throttle = 0.6
		main._touch_clutch = 0.4
	var path := OS.get_environment("TEMP").replace("\\", "/") + "/lever_check.png"
	root.get_texture().get_image().save_png(path)
	print("saved %s" % path)
	quit()
