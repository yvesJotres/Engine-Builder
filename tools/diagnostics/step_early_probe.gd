extends SceneTree

# Probe of the early-return path in EngineSim.step. Run: godot --headless --path . -s tools/diagnostics/step_early_probe.gd
const DT := 1.0 / 60.0


func _init() -> void:
	await process_frame
	var p: Dictionary = Presets.PRESETS["honda_cbr250rr"]
	var spec := EngineSpec.new()
	for key in p.keys():
		spec.set(key, p[key])
	var sim := EngineSim.new()
	sim.exhaust_solver = true
	for i in 6:
		sim.step(DT, spec, 0.0, true, true, false, false, 1.0)
		print("f%d rpm %.1f omega %.3f run %s gas %.4f intake %.0f starter last %s" % [i, sim.rpm, sim.omega, str(sim.running), sim._gas_torque, sim.intake.pressure, str(sim.last_starter_held)])
	quit(0)
