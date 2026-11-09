extends SceneTree

func _init() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child.call_deferred(main)
	await process_frame
	await process_frame
	main._set_setup_open(true)
	main._panel._select_category(1)
	main._panel._controls["intake_display"].select(1)
	main._on_panel_changed()
	for i in 20:
		await process_frame
	var path := ProjectSettings.globalize_path("res://tools/diagnostics/out/intake_options.png")
	var err := root.get_texture().get_image().save_png(path)
	print("Screenshot %s result %d" % [path, err])
	quit(err)
