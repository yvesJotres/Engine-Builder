extends SceneTree


func _init() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var failures := 0
	for displacement in [149.2, 600.0]:
		main._sim = EngineSim.new()
		main._sim.audio_enabled = false
		main.spec = EngineSpec.new()
		main.spec.displacement_cc = displacement
		if displacement > 200.0:
			main.spec.cylinders = 4
		main._keyboard_starting = false
		var throttle := 0.0
		for i in 240:
			var held := i < 60
			main._update_keyboard_starter(held)
			throttle = minf(throttle + 2.0 / 60.0, 1.0) if held and not main._keyboard_starting else move_toward(throttle, 0.0, 3.0 / 60.0)
			main._sim.step(1.0 / 60.0, main.spec, throttle, true, main._keyboard_starting, false, false, 1.0)
		var ok: bool = main._sim.running and main._sim.rpm > 500.0
		print("%s keyboard start %.0f cc: %.0f rpm" % ["PASS" if ok else "FAIL", displacement, main._sim.rpm])
		if not ok:
			failures += 1
	quit(1 if failures else 0)
