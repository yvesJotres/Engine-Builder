extends SceneTree

# Diagnostic: the TRX520 cylinder through the cycle that stalls it, after the throttle opens at idle. Print only.
func _init() -> void:
	await process_frame
	var spec := EngineSpec.new()
	var p: Dictionary = Presets.PRESETS["honda_trx520"]
	for key in p.keys():
		spec.set(key, p[key])
	var sim := EngineSim.new()
	for i in 720:
		sim.step(1.0 / 60.0, spec, 0.0, true, true, false, false, 1.0)
	for i in 900:
		sim.step(1.0 / 60.0, spec, 0.0, true, false, false, false, 1.0)
	var c = sim.cylinders[0]
	print("idle %.0f rpm at cylinder phase %.0f" % [sim.rpm, fposmod(c.phi, 720.0)])
	# step by small slices so each shows the cylinder
	var last_burn := -1.0
	for i in 400:
		sim.step(1.0 / 3600.0, spec, 1.0, true, false, false, false, 1.0)
		if i % 8 == 0 or sim.rpm < 300.0:
			print("step %3d: rpm %5.0f phase %5.0f  p %6.2f bar  T %5.0f K  mass %.3f g  burn left %.0f J / %.0f J  fired %s  gas %+.0f" % [i, sim.rpm, fposmod(c.phi, 720.0), c.pressure / 1e5, c.temp, c.mass * 1000.0, c.burn_energy_left, c.burn_energy, str(c._fired), sim._gas_torque])
		if sim.rpm < 50.0:
			break
	quit(0)
