extends SceneTree

# Full-throttle pull, averaged per 1000 rpm: volumetric efficiency, residual fraction, charge temperature at intake
# closing, intake pressure, and the mixture. Diagnostic only, no physics change.
# Run: godot --headless --path . -s tools/diagnostics/lowrpm_probe.gd -- honda_cbr250rr_2020

const DT := 1.0 / 60.0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var preset_id := args[0] if args.size() > 0 else "honda_cbr250rr_2020"
	var spec := DynoRunner.spec_for(preset_id)
	if spec == null:
		print("Unknown preset: %s" % preset_id)
		quit(2)
		return
	var sim := EngineSim.new()
	sim.fuel.set_kind(spec.fuel)
	var dyno := DynoTest.new()
	dyno.start(spec, sim)
	var acc := {}
	var frames := 0
	while dyno.active() and frames < DynoRunner.MAX_FRAMES:
		dyno.advance(DT, sim, spec, 1.0, true)
		frames += 1
		if dyno.phase != DynoTest.Phase.PULL or sim.clutch_engage < 0.99 or sim.rpm < 2000.0 or sim.limiter_active:
			continue
		var bin := int(sim.rpm / 1000.0) * 1000
		if not acc.has(bin):
			acc[bin] = {"n": 0.0, "ve": 0.0, "resid": 0.0, "ivc_c": 0.0, "intake_kpa": 0.0, "lambda": 0.0}
		var a: Dictionary = acc[bin]
		a.n += 1.0
		a.ve += EngineMetrics.volumetric_efficiency(sim)
		a.resid += EngineMetrics.residual_fraction(sim)
		a.ivc_c += EngineMetrics.ivc_temp_c(sim)
		a.intake_kpa += sim.intake.pressure / 1000.0
		a.lambda += sim.o2_lambda()
	print("rpm    VE     residual  IVC_C   intake_kPa  lambda")
	var keys := acc.keys()
	keys.sort()
	for k in keys:
		var a: Dictionary = acc[k]
		var n: float = a.n
		print("%5d  %5.3f   %6.3f   %6.1f   %8.1f    %5.3f" % [k, a.ve / n, a.resid / n, a.ivc_c / n, a.intake_kpa / n, a.lambda / n])
	quit(0)
