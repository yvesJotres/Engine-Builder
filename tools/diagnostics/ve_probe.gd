extends SceneTree

# Volumetric efficiency, intake pressure and mass flow against rpm during a full-throttle pull, averaged per 500 rpm.
# Diagnostic only. Run: godot --headless --path . -s tools/diagnostics/ve_probe.gd -- honda_cbr250rr_sp_qs [native|gd]

const DT := 1.0 / 60.0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var preset_id := args[0] if args.size() > 0 else "honda_cbr250rr_sp_qs"
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
	var sum_ve := {}
	var sum_p := {}
	var count := {}
	var frames := 0
	while dyno.active() and frames < 200000:
		dyno.advance(DT, sim, spec, 1.0, true)
		frames += 1
		if dyno.phase != DynoTest.Phase.PULL or sim.clutch_engage < 0.99 or sim.rpm < 1000.0:
			continue
		var bin := int(sim.rpm / 500.0) * 500
		sum_ve[bin] = float(sum_ve.get(bin, 0.0)) + EngineMetrics.volumetric_efficiency(sim)
		sum_p[bin] = float(sum_p.get(bin, 0.0)) + sim.intake.pressure
		count[bin] = int(count.get(bin, 0)) + 1
	print("rpm_bin,volumetric_efficiency,intake_kpa,samples")
	var bins := count.keys()
	bins.sort()
	for b in bins:
		var n := float(count[b])
		print("%d,%.3f,%.1f,%d" % [b, float(sum_ve[b]) / n, float(sum_p[b]) / n / 1000.0, count[b]])
	quit(0)
