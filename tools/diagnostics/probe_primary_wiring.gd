extends SceneTree

# The header primary diameter changed 48 -> 39 mm on the CBR1000RR-R and the power did not move by a watt. Two candidate
# explanations: the diameter never reaches the gas model in the live (non-solver) path, or it reaches it and genuinely
# does nothing at this operating point.
#
# The live path sets the exhaust valve's downstream pressure from _exhaust_pressure(), which is P0 + a mean backpressure
# from Backpressure - a steady term, so a primary only shifts pumping loss by a fraction of a N m. The 1D solver path
# (sim.exhaust_solver = true) is the one that resolves waves, and docs call it the offline path, which is exactly what a
# dyno pull is. This measures both, at several primary diameters.
# Run: godot --headless --path . -s res://tools/diagnostics/probe_primary_wiring.gd

const RPMS := [4000.0, 8000.0, 12000.0]
const BORES := [48.0, 39.0, 34.0]


func _hold(sim: EngineSim, spec: EngineSpec, rpm: float) -> float:
	var dt := sim.physics_dt
	var revs := 0.0
	sim.running = true
	while revs < 12.0:
		sim.omega = rpm * TAU / 60.0
		sim.rpm = rpm
		sim.step(dt, spec, 1.0, true, false, true, false, 1.0)
		revs += rpm * dt / 60.0
	return Units.power_kw(sim.cycle_brake_torque, rpm) / 0.7457 * EngineSim.DRIVE_EFFICIENCY


func _init() -> void:
	await process_frame
	var preset: Dictionary = Presets.PRESETS["honda_cbr1000rrr_sp"]
	for solver in [false, true]:
		print("")
		print("solver %s" % str(solver))
		print("   %6s %8s %8s %8s" % ["primary", "hp @4k", "hp @8k", "hp @12k"])
		for primary in BORES:
			var spec := EngineSpec.new()
			for key in preset:
				spec.set(key, preset[key])
			spec.header_primary_mm = primary
			var sim := EngineSim.new()
			sim.audio_enabled = false
			sim.exhaust_solver = solver
			sim.physics_dt = 1.0 / 2400.0
			sim.set_audio_layout(ExhaustLayout.build(spec, [], Vector3(0.0, 2.0, 0.0), Ground.Y, Vector3(0.0, 3.0, -5.95)), spec.cylinders)
			var out := []
			for rpm in RPMS:
				out.append(_hold(sim, spec, rpm))
			print("   %6.0f %8.1f %8.1f %8.1f" % [primary, out[0], out[1], out[2]])
	quit(0)
