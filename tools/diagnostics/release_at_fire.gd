extends SceneTree

# A rider lets go of the starter as soon as the engine fires. Does it carry on and idle? Runs the CBR150R and prints the rpm
# each second for five seconds after the release, for several starts that differ in when the starter is let go.
# Run: godot --headless -s tools/diagnostics/release_at_fire.gd
func _init() -> void:
	await process_frame
	var spec := EngineSpec.new()
	for extra in [0, 20, 60]: # frames the starter is held after the first fire
		var sim := EngineSim.new()
		var frames := 0
		while not sim.running and frames < 1800:
			sim.step(1.0 / 60.0, spec, 0.0, true, true, false, false, 1.0)
			frames += 1
		for i in extra:
			sim.step(1.0 / 60.0, spec, 0.0, true, true, false, false, 1.0)
		var line := ""
		for s in 5:
			for i in 60:
				sim.step(1.0 / 60.0, spec, 0.0, true, false, false, false, 1.0)
			line += " %.0f" % sim.rpm
		print("starter held %2d frames after the first fire: rpm each second after release:%s" % [extra, line])
	quit()
