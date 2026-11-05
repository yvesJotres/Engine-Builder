extends SceneTree

# rpm, ECU air factor and spark trim every 5 frames from the first fire, starter held for 60 frames then released.
func _init() -> void:
	await process_frame
	var spec := EngineSpec.new()
	var sim := EngineSim.new()
	var frames := 0
	while not sim.running and frames < 1800:
		sim.step(1.0 / 60.0, spec, 0.0, true, true, false, false, 1.0)
		frames += 1
	print("first fire after %d frames, rpm %.0f" % [frames, sim.rpm])
	for i in 150:
		var held := i < 60
		sim.step(1.0 / 60.0, spec, 0.0, true, held, false, false, 1.0)
		if i % 5 == 4:
			print("f %3d %s rpm %6.0f running %s air x%.2f spark trim %5.1f manifold %5.1f kPa" % [i + 1, "held " if held else "free ", sim.rpm, sim.running, sim.ecu.air_factor(), sim.ecu.trim, sim.intake.pressure / 1000.0])
	quit()
