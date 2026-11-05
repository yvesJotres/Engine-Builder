extends SceneTree

# Diagnostic: idle, then full throttle in neutral, printing rpm and manifold pressure every half second. Run:
# godot --headless -s tools/diagnostics/wot_trace.gd

const DT := 1.0 / 60.0


func _init() -> void:
	var spec := EngineSpec.new()
	spec.flywheel_radius_mm = 75.0 # experiment: a larger flywheel radius than the bore-based default
	print("rotating inertia %.4f kg·m²" % spec.rotating_inertia())
	var sim := EngineSim.new()
	for i in 600:
		sim.step(DT, spec, 0.0, true, true, true, false, 1.0)
	for i in 1200:
		sim.step(DT, spec, 0.0, true, false, true, false, 1.0)
	print("idle: rpm %.0f running %s manifold %.1f kPa" % [sim.rpm, sim.running, sim.intake.pressure / 1000.0])
	for i in 2400:
		sim.step(DT, spec, 1.0, true, false, true, false, 1.0)
		if i % 6 == 5 and i < 120:
			var c := sim.cylinders[0]
			print("t %.2f s  rpm %6.0f  manifold %5.1f kPa  torque %6.2f  cyl phi %5.0f  T %5.0f K  p %5.1f bar  mass %.3f g  burn %.1f J  left %.1f J" % [
				(i + 1) * DT, sim.rpm, sim.intake.pressure / 1000.0, sim.torque, fmod(c.phi, 720.0), c.temp, c.pressure / 100000.0, c.mass * 1000.0, c.burn_energy, c.burn_energy_left])
		if i % 30 == 29:
			print("t %.1f s  rpm %6.0f  running %s  manifold %5.1f kPa  torque %6.2f  limiter %s" % [
				(i + 1) * DT, sim.rpm, sim.running, sim.intake.pressure / 1000.0, sim.torque, sim.limiter_active])
	quit()
