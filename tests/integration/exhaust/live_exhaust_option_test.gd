extends SceneTree

func _init() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child.call_deferred(main)
	await process_frame
	await process_frame
	assert(not main._sim.exhaust_solver)
	main._panel._controls["live_exhaust_physics"].select(1)
	main._on_panel_changed()
	assert(main.spec.live_exhaust_physics and main._sim.exhaust_solver)
	main._panel._controls["muffler_style"].select(2)
	main._on_panel_changed()
	assert(main.spec.muffler_style == "short")
	assert(main._sim._audio_layout != null)
	main._panel._controls["live_exhaust_physics"].select(0)
	main._on_panel_changed()
	assert(not main._sim.exhaust_solver)
	main.free()
	print("live_exhaust_option_test: PASS")
	quit(0)
