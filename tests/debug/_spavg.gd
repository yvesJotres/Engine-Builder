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
	for i in 3 * 60:
		for j in 40:
			sim.step(sim.physics_dt, spec, 0.0, true, true, false, false, 1.0)
	var sum0 := 0.0
	var sumw := 0.0
	var neg_mass := 0.0
	var pos_mass := 0.0
	for j in 2400:
		sim.step(sim.physics_dt, spec, 0.0, true, false, false, false, 1.0)
		for c in sim.cylinders:
			sum0 += c.exhaust_mdot * sim.physics_dt
			if c.exhaust_mdot < 0.0:
				neg_mass += c.exhaust_mdot * sim.physics_dt
			else:
				pos_mass += c.exhaust_mdot * sim.physics_dt
	print("AVG net mass per second into pipes %.6f kg  (out %.6f, back %.6f)" % [sum0, pos_mass, neg_mass])
	print("AVG rpm %.0f" % sim.rpm)
	quit()
