extends SceneTree

# Where does the CBR250RR's +5% at 12,500 rpm come from? The pre-checkpoint tree (39df036) does not run - it references
# files and EngineSpec members that only exist later - so a code bisect is not available. This measures the sensitivity
# instead: the same wide-open hold with heat transfer scaled, and with the 1D pipe solver on and off. A +5% that tracks
# wall_heat_scale is a heat-transfer problem; one that tracks the solver is a wave-tuning problem; one that moves with
# neither is in the cylinder's gas state or the valve flow.
# Run: godot --headless --path . -s res://tools/diagnostics/probe_cbr_power_sensitivity.gd

const RPM := 12500.0
const TARGET_KW := 28.0


func _hold(sim: EngineSim, spec: EngineSpec) -> Dictionary:
	var dt := sim.physics_dt
	var sum_t := 0.0
	var sum_r := 0.0
	var n := 0
	var revs := 0.0
	sim.running = true
	while revs < 8.0:
		sim.omega = RPM * TAU / 60.0
		sim.rpm = RPM
		sim.step(dt, spec, 1.0, true, false, true, false, 1.0)
		revs += RPM * dt / 60.0
		if revs > 4.0:
			sum_t += sim.torque
			sum_r += sim.rpm
			n += 1
	return {"torque": sum_t / maxf(float(n), 1.0), "rpm": sum_r / maxf(float(n), 1.0)}


func _run(label: String, wall_scale: float, solver: bool) -> void:
	var preset: Dictionary = Presets.PRESETS["honda_cbr250rr"]
	var spec := EngineSpec.new()
	for key in preset:
		spec.set(key, preset[key])
	spec.wall_heat_scale = wall_scale
	var sim := EngineSim.new()
	sim.audio_enabled = false
	sim.physics_dt = 1.0 / 2400.0
	sim.exhaust_solver = solver
	var sample := _hold(sim, spec)
	var kw := Units.power_kw(sample.torque, sample.rpm)
	print("%-28s wall_heat %.1f  solver %-5s  %6.2f N m  %6.2f kW  (%+.1f%% vs %.0f kW)" % [
		label, wall_scale, str(solver), sample.torque, kw, (kw / TARGET_KW - 1.0) * 100.0, TARGET_KW])


func _init() -> void:
	await process_frame
	_run("as shipped", 1.0, false)
	_run("no wall heat", 0.0, false)
	_run("double wall heat", 2.0, false)
	_run("1D pipe solver on", 1.0, true)
	quit(0)
