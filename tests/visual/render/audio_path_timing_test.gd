extends SceneTree


func _init() -> void:
	var ok := true
	for pipe_solver in [false, true]:
		var spec := EngineSpec.new()
		var sim := EngineSim.new()
		sim.exhaust_solver = pipe_solver
		sim.physics_dt = 1.0 / 1200.0
		var total := 0
		var started := Time.get_ticks_usec()
		for i in 30:
			sim.step(1.0 / 60.0, spec, 0.0, true, true, false, false, 1.0)
			var flow: PackedFloat32Array = sim.exhaust.take_flow() if pipe_solver and sim.exhaust != null else sim.take_blowdown()
			total += flow.size()
			sim.take_intake_flow()
		var elapsed := (Time.get_ticks_usec() - started) / 1000000.0
		var expected := 22050
		print("%s: %d samples in 0.5 simulated seconds, %.3f s CPU" % ["pipe" if pipe_solver else "live", total, elapsed])
		ok = ok and absi(total - expected) <= 100
	var renderer := AudioRenderer.new()
	root.add_child(renderer)
	var error := [""]
	renderer.render_failed.connect(func(message: String) -> void: error[0] = message)
	renderer.render(EngineSpec.new(), null, 0.1, 48000)
	ok = ok and not error[0].is_empty()
	renderer.free()
	print("RESULT: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
