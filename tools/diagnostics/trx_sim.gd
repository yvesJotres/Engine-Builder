extends SceneTree

# Diagnostic: the TRX520 in the bare simulation: idle, then full throttle, rpm every frame at the start. Print only.
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
	print("idle %.0f rpm, cr %.1f, flywheel %.2f kg r %.0f mm, inertia %.4f" % [sim.rpm, spec.compression_ratio, spec.flywheel_kg, spec.flywheel_radius_mm, spec.rotating_inertia()])
	for i in 12:
		sim.step(1.0 / 60.0, spec, 1.0, true, false, false, false, 1.0)
		print("frame %2d: rpm %5.0f running %s gas torque %+.1f manifold %.1f kPa" % [i + 1, sim.rpm, str(sim.running), sim._gas_torque, sim.intake.pressure / 1000.0])
	quit(0)
