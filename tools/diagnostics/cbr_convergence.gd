extends SceneTree

# Fixed-speed comparison: same warm-up and sample duration at every timestep.
func _init() -> void:
	Cylinder.use_native = not OS.get_cmdline_user_args().has("--gd-only")
	for hz in [1200, 2400, 3600, 7200, 14400, 28800]:
		for target in [11000.0, 12500.0]:
			var spec := EngineSpec.new()
			for key in Presets.PRESETS.honda_cbr250rr:
				spec.set(key, Presets.PRESETS.honda_cbr250rr[key])
			var sim := EngineSim.new()
			sim.audio_enabled = false
			sim.physics_dt = 1.0 / hz
			var sum := 0.0
			var start := Time.get_ticks_usec()
			for i in hz * 2:
				sim.rpm = target
				sim.omega = target * TAU / 60.0
				sim.step(sim.physics_dt, spec, 1.0, true, false, true, false, 1.0)
				if i >= hz:
					sum += sim.torque
			print("%d Hz %.0f rpm: %.3f Nm %.3f kW wall %.1f ms" % [hz, target, sum / hz, Units.power_kw(sum / hz, target), (Time.get_ticks_usec() - start) / 1000.0])
	quit()
