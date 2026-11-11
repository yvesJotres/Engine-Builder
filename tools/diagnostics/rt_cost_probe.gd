extends SceneTree

# Real-time budget probe: wall-clock time to simulate one second of CBR150R at full throttle, for each exhaust mode.
# Real time means the ratio stays below 1.0.
const PHYS_DT := 1.0 / 2400.0


func _init() -> void:
	for pipe in [false, true]:
		var spec := EngineSpec.new()
		var preset: Dictionary = Presets.PRESETS[OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "honda_cbr150r"]
		for key in preset.keys():
			spec.set(key, preset[key])
		var sim := EngineSim.new()
		sim.physics_dt = PHYS_DT
		sim.exhaust_solver = pipe
		var t := 0.0
		while t < 2.0: # warm up at idle, starter held
			sim.step(1.0 / 60.0, spec, 0.0, true, true, true, false, 1.0)
			t += 1.0 / 60.0
		var start := Time.get_ticks_usec()
		t = 0.0
		while t < 1.0:
			sim.step(1.0 / 60.0, spec, 0.6, true, false, true, false, 1.0)
			t += 1.0 / 60.0
		var elapsed := (Time.get_ticks_usec() - start) / 1000000.0
		print("pipe=%s  wall %.3f s per 1 s simulated  (ratio %.2f, rpm %.0f)" % [str(pipe), elapsed, elapsed, sim.rpm])
	quit(0)
