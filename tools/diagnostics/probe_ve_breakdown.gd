extends SceneTree

# Why is the CBR1000RR-R 31% low at 13,900 rpm and 51% high at 4,000? Split the torque into its parts:
#   IMEP = BMEP + FMEP, and VE says whether the cylinder filled at all.
# If VE falls off with rpm the answer is breathing (runner/valve/port); if VE holds and FMEP climbs, it is friction;
# if both hold, it is combustion phasing or heat transfer.
# Run: godot --headless --path . -s res://tools/diagnostics/probe_ve_breakdown.gd [preset]

const RPMS := [4000.0, 6000.0, 8000.0, 10000.0, 12000.0, 13500.0]


func _hold(sim: EngineSim, spec: EngineSpec, rpm: float) -> void:
	var dt := sim.physics_dt
	var revs := 0.0
	sim.running = true
	while revs < 16.0:
		sim.omega = rpm * TAU / 60.0
		sim.rpm = rpm
		sim.step(dt, spec, 1.0, true, false, true, false, 1.0)
		revs += rpm * dt / 60.0


func _init() -> void:
	var argv := OS.get_cmdline_user_args()
	var id: String = argv[0] if argv.size() > 0 else "honda_cbr1000rrr_sp"
	var preset: Dictionary = Presets.PRESETS[id]
	var spec := EngineSpec.new()
	for key in preset:
		spec.set(key, preset[key])
	print("%s: %d cyl, %.0f cc, redline %.0f, header %s, runner %.0f mm" % [
		id, spec.cylinders, spec.displacement_cc, spec.redline_rpm, str(spec.header), spec.runner_length_m * 1000.0])
	print("%7s %8s %8s %8s %7s %8s %7s" % ["rpm", "BMEP bar", "IMEP bar", "FMEP bar", "VE", "torque", "hp rw"])
	var sim := EngineSim.new()
	sim.audio_enabled = false
	sim.physics_dt = 1.0 / 2400.0
	for rpm in RPMS:
		_hold(sim, spec, rpm)
		var bmep := EngineMetrics.bmep_pa(sim) / 1.0e5
		var imep := EngineMetrics.imep_pa(sim) / 1.0e5
		var fmep := EngineMetrics.fmep_pa(sim) / 1.0e5
		var ve := EngineMetrics.volumetric_efficiency(sim)
		var hp_rw := Units.power_kw(sim.torque, sim.rpm) / 0.7457 * EngineSim.DRIVE_EFFICIENCY
		print("%7.0f %8.2f %8.2f %8.2f %7.3f %8.2f %7.1f" % [rpm, bmep, imep, fmep, ve, sim.torque, hp_rw])
	quit(0)
