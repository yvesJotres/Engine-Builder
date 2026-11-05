extends SceneTree

func _init() -> void:
	await process_frame
	var p: Dictionary = Presets.PRESETS["Ducati Panigale V4 (1,103 cc)"]
	var spec := EngineSpec.new()
	for key in p.keys():
		spec.set(key, p[key])
	var sim := EngineSim.new()
	for i in 600:
		sim.step(1.0 / 60.0, spec, 0.0, true, true, false, false, 1.0)
		if i % 60 == 59:
			print("crank %2d s: rpm %6.0f running %s gas %6.2f" % [(i + 1) / 60, sim.rpm, sim.running, sim._gas_torque])
	quit()
