extends SceneTree

# Engine speed and phase during the dyno's start, every 0.1 s, to see why an engine stalls at idle.
# Diagnostic only. Run: godot --headless --path . -s tools/diagnostics/dyno_start_probe.gd -- amg_v6_w17 [native|gd]

const DT := 1.0 / 60.0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var preset_id := args[0] if args.size() > 0 else "amg_v6_w17"
	Cylinder.use_native = not (args.size() > 1 and args[1] == "gd")
	var spec := DynoRunner.spec_for(preset_id)
	if spec == null:
		print("Unknown preset: %s" % preset_id)
		quit(2)
		return
	var sim := EngineSim.new()
	sim.fuel.set_kind(spec.fuel)
	var dyno := DynoTest.new()
	dyno.start(spec, sim)
	var frames := 0
	var next_print := 0.0
	var t := 0.0
	print("t(s)  phase  rpm    running  intake_kpa  fresh_air_last_kg/s")
	while dyno.active() and t < 4.0:
		dyno.advance(DT, sim, spec, 1.0, true)
		frames += 1
		t = frames * DT
		if t >= next_print:
			print("%.2f  %5d  %6.0f  %5s  %9.1f" % [t, dyno.phase, sim.rpm, str(sim.running), sim.intake.pressure / 1000.0])
			next_print += 0.1
	print("status: %s" % dyno.status)
	quit(0)
