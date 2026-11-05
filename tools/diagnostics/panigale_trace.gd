extends SceneTree

func _init() -> void:
	await process_frame
	var p: Dictionary = Presets.PRESETS["Ducati Panigale V4 (1,103 cc)"]
	var spec := EngineSpec.new()
	for key in p.keys():
		spec.set(key, p[key])
	var sim := EngineSim.new()
	for i in 20:
		sim.step(1.0 / 60.0, spec, 0.0, true, true, false, false, 1.0)
	print("cranked 20 frames: rpm %.0f running %s" % [sim.rpm, sim.running])
	for i in 90:
		sim.step(1.0 / 60.0, spec, 0.0, true, false, false, false, 1.0)
		if i % 6 == 5:
			print("t %.2f rpm %6.0f running %s gas %7.2f trim %5.1f air x%.3f manifold %5.1f kPa" % [(i+1)/60.0, sim.rpm, sim.running, sim._gas_torque, sim.ecu.trim, sim.ecu.air_factor(), sim.intake.pressure / 1000.0])
	quit()
