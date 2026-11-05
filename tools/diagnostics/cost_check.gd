extends SceneTree

# Wall-clock cost of simulating one second of engine time at each physics step rate, for the CBR150R at idle.
# A phone is slower than a PC: if a second of engine time costs more than a second of wall time, the game runs in slow motion.
# Run: godot --headless -s tools/diagnostics/cost_check.gd
func _init() -> void:
	await process_frame
	for rate in [1200, 2400, 3600, 7200]:
		var spec := EngineSpec.new()
		var sim := EngineSim.new()
		sim.physics_dt = 1.0 / rate
		for i in 180: # start it first
			sim.step(1.0 / 60.0, spec, 0.0, true, true, false, false, 1.0)
		var t0 := Time.get_ticks_usec()
		for i in 120: # two seconds of engine time at 60 fps
			sim.step(1.0 / 60.0, spec, 0.0, true, false, false, false, 1.0)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		print("%4d steps a second: %6.1f ms of wall time per second of engine time" % [rate, ms / 2.0])
	quit()
