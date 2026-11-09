extends SceneTree


func _init() -> void:
	var spec := EngineSpec.new()
	spec.cylinders = 4
	var sim := EngineSim.new()
	sim.physics_dt = 1.0 / 2400.0
	for i in 60:
		sim.step(1.0 / 60.0, spec, 0.0, true, false, true, true, 1.0)
	var ok := sim.cylinders.size() == 4 and sim.rpm == 0.0 and sim.omega == 0.0
	ok = ok and sim.brake > 0.99 and sim.clutch_engage < 0.01 and sim.take_blowdown().is_empty()
	sim.step(1.0 / 60.0, spec, 0.0, true, true, true, false, 1.0)
	ok = ok and sim.rpm > 0.0
	var sound := EngineSound.new()
	root.add_child(sound)
	sound.setup(spec)
	sound.push_flow(PackedFloat32Array([1.0, 0.5]))
	sound.clear_pending()
	ok = ok and sound._flow.is_empty() and not sound.playing
	sound.free()
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main._process(1.0 / 60.0)
	ok = ok and not main._sound.playing
	main._touch_starter = true
	for i in 60:
		main._process(1.0 / 60.0)
	ok = ok and main._sim.rpm > 1.0 and main._sound.playing and not main._sound.stream_paused
	main.free()
	print("RESULT: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
