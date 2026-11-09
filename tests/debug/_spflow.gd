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
	var mmin := 1e9
	var mmax := -1e9
	var pmin := 1e9
	var pmax := -1e9
	var neg := 0
	var n := 0
	for j in 2400:
		sim.step(sim.physics_dt, spec, 0.0, true, false, false, false, 1.0)
		for c in sim.cylinders:
			mmin = minf(mmin, c.exhaust_mdot)
			mmax = maxf(mmax, c.exhaust_mdot)
			pmin = minf(pmin, c.exhaust_power)
			pmax = maxf(pmax, c.exhaust_power)
			if c.exhaust_mdot < 0.0:
				neg += 1
			n += 1
	print("FLOW exhaust_mdot min %.5f max %.5f  power min %.1f max %.1f  negative %d of %d" % [mmin, mmax, pmin, pmax, neg, n])
	print("FLOW backpressure_kpa %.1f rpm %.0f" % [sim.backpressure_pa() / 1000.0, sim.rpm])
	quit()
