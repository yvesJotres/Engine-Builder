extends SceneTree

# Renders six seconds of the ZX-25R at idle with the game's own renderer, from the loaded main scene. Print only.
# Run: godot --headless --path . -s tests/debug/zx_idle_render.gd -- <output_dir>
func _init() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://"
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 30:
		await process_frame
	main._panel.set_preset("kawasaki_zx25r") if main._panel.has_method("set_preset") else null
	for i in 30:
		await process_frame
	var layout := ExhaustLayout.build(main.spec, main._model.exhaust_ports(), main._model.crank_position(), Ground.Y, main._drivetrain.rear_axle)
	main._audio_renderer.render_completed.connect(func(path: String) -> void:
		print("RENDERED: " + path)
		quit())
	main._audio_renderer.render(main.spec, layout, 6.0, 44100, 16, 0.0, out)
