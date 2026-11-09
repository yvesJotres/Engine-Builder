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
	var g = sim.exhaust
	for k in 8:
		for j in 300:
			sim.step(sim.physics_dt, spec, 0.0, true, false, false, false, 1.0)
		var mass := 0.0
		var energy := 0.0
		var tmin := 1e9
		var tmax := -1e9
		for i in g._n:
			mass += g._rho[i] * g._area[i] * g._dx[i]
			energy += g._re[i] * g._area[i] * g._dx[i]
		for i in g._n:
			var t: float = g._pressure(i) / maxf(g._rho[i] * 287.0, 1e-6)
			tmin = minf(tmin, t)
			tmax = maxf(tmax, t)
		print("MASS t%d total %.6f energy %.1f  cell T %.0f..%.0f K  port0 %.1f kPa  cell_n %d" % [k, mass, energy, tmin, tmax, g.port_pressure(0) / 1000.0, g._n])
	quit()
