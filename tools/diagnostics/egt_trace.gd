extends SceneTree

# Diagnostic: traces one cylinder's gas temperature through a cycle at full throttle, to see where the
# exhaust temperature sensor's reading comes from. Print only: run with godot --headless -s tools/diagnostics/egt_trace.gd

func _init() -> void:
	await process_frame
	var spec := EngineSpec.new()
	var sim := EngineSim.new()
	sim.physics_dt = 1.0 / 3600.0
	for i in 720:
		sim.step(1.0 / 60.0, spec, 0.0, true, true, false, false, 1.0)
	for i in 600:
		sim.step(1.0 / 60.0, spec, 0.6, true, false, false, false, 1.0)
	print("rpm %.0f  running %s  limiter %s  fuel %.3f kg  sensor exhaust %.0f C" % [sim.rpm, sim.running, sim.limiter_active, sim.fuel.mass_kg, sim.exhaust_temp_c()])
	var c = sim.cylinders[0]
	for i in 60:
		sim.step(sim.physics_dt, spec, 0.6, true, false, false, false, 1.0)
		print("phi %6.1f  temp %6.0f K  pressure %6.2f bar  mass %.5f g  burnt %.2f" % [fposmod(c.phi, 720.0), c.temp, c.pressure / 1e5, c.mass * 1000.0, c._burnt])
	print("running %s limiter %s fuel %.3f kg, cylinder 0 last_lambda %.2f" % [sim.running, sim.limiter_active, sim.fuel.mass_kg, c.last_lambda])
	print("exhaust_temp recorded for cylinder 0: %.0f K" % c.exhaust_temp)
	quit(0)
