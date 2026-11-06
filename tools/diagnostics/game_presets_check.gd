extends SceneTree

# Diagnostic: every preset in the real main scene, chosen through the panel: idle rpm after a start, then rpm after two seconds
# of full throttle in neutral. Print only.
func _init() -> void:
	await process_frame
	var index := 0
	for name in Presets.PRESETS:
		var main: Node = load("res://scenes/main.tscn").instantiate()
		root.add_child(main)
		await process_frame
		await process_frame
		main._panel._on_preset_selected(index)
		await process_frame
		main._ignition = true
		main._touch_starter = true
		for i in 700:
			main._process(1.0 / 60.0)
		main._touch_starter = false
		for i in 900:
			main._process(1.0 / 60.0)
		var idle: float = main._sim.rpm
		var trim: float = main._sim.ecu.trim
		main._touch_throttle = 1.0
		for i in 120:
			main._process(1.0 / 60.0)
		print("%-32s idle %5.0f rpm (trim %+.0f)  full throttle 2 s: %5.0f rpm  running %s" % [name, idle, trim, main._sim.rpm, str(main._sim.running)])
		main.queue_free()
		await process_frame
		index += 1
	quit(0)
