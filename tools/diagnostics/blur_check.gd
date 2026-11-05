extends SceneTree

# Visual check, needs a window (not headless): turns motion blur on, starts the engine and holds the throttle for a few
# seconds, then saves a screenshot to the temp folder. Run: godot --path . -s tools/diagnostics/blur_check.gd

const FRAMES := 300


func _init() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main._blur.set_enabled(true)
	for i in FRAMES:
		main._touch_starter = i < 120 # crank for 2 s, then let it fire
		main._touch_throttle = i >= 120
		await process_frame
	var image := root.get_texture().get_image()
	var path := OS.get_environment("TEMP").replace("\\", "/") + "/blur_check.png"
	image.save_png(path)
	print("saved %s, blur %s, rpm %.0f" % [path, main._blur.enabled, main._sim.rpm])
	quit()
