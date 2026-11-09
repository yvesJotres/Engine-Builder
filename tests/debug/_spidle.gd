extends SceneTree
func _init() -> void:
	var spec := EngineSpec.new()
	var p: Dictionary = Presets.PRESETS["harley_sportster_883"]
	for key in p.keys():
		spec.set(key, p[key])
	var sim := EngineSim.new()
	sim.physics_dt = 1.0 / 2400.0
	sim.exhaust_solver = true
	sim.fuel.set_kind(spec.fuel)
	for i in 4 * 60:
		for j in 40:
			sim.step(sim.physics_dt, spec, 0.0, true, true, false, false, 1.0)
	for sec in 10:
		for j in 60:
			sim.step(sim.physics_dt, spec, 0.0, true, false, false, false, 1.0)
		print("T%02d rpm %.0f trim %.2f air %.2f bp_kpa %.1f torque %.2f" % [sec, sim.rpm, sim.ecu.trim, sim.ecu.air_factor(), sim.backpressure_pa() / 1000.0, sim.torque])
	quit()
