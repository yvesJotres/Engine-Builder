extends SceneTree

# Splits the dyno pull's output into indicated, friction and pumping pressure, breathing and combustion timing,
# averaged per 1000 rpm during full-throttle pulls. Diagnostic only.
# Run: godot --headless --path . -s tools/diagnostics/power_breakdown.gd -- honda_cbr250rr_sp_qs [key=value overrides]

const DT := 1.0 / 60.0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var preset_id := args[0] if args.size() > 0 else "honda_cbr250rr_sp_qs"
	var spec := DynoRunner.spec_for(preset_id)
	if spec == null:
		print("Unknown preset: %s" % preset_id)
		quit(2)
		return
	for i in range(1, args.size()):
		var kv: PackedStringArray = args[i].split("=")
		spec.set(kv[0], float(kv[1]))
	var sim := EngineSim.new()
	sim.fuel.set_kind(spec.fuel)
	var dyno := DynoTest.new()
	dyno.start(spec, sim)
	var acc := {}
	var frames := 0
	while dyno.active() and frames < 200000:
		dyno.advance(DT, sim, spec, 1.0, true)
		frames += 1
		if dyno.phase != DynoTest.Phase.PULL or sim.clutch_engage < 0.99 or sim.rpm < 2000.0 or sim.limiter_active:
			continue
		var bin := int(sim.rpm / 1000.0) * 1000
		if not acc.has(bin):
			acc[bin] = {"n": 0.0, "imep": 0.0, "bmep": 0.0, "fmep": 0.0, "ve": 0.0, "ca50": 0.0, "burn": 0.0, "lam": 0.0, "pk": 0.0, "intake": 0.0}
		var a: Dictionary = acc[bin]
		a.n += 1.0
		a.imep += EngineMetrics.imep_pa(sim) / 1000.0
		a.bmep += EngineMetrics.bmep_pa(sim) / 1000.0
		a.fmep += EngineMetrics.fmep_pa(sim) / 1000.0
		a.ve += EngineMetrics.volumetric_efficiency(sim)
		a.ca50 += EngineMetrics.ca50_deg(sim)
		a.burn += EngineMetrics.burn_10_90_deg(sim)
		a.lam += sim.o2_lambda()
		a.pk += EngineMetrics.peak_pressure_pa(sim) / 1000.0
		a.intake += sim.intake.pressure / 1000.0
	print("rpm    imep_kPa bmep_kPa fmep_kPa  VE    CA50_deg burn10_90  lambda  peakP_kPa intake_kPa")
	var keys := acc.keys()
	keys.sort()
	for k in keys:
		var a: Dictionary = acc[k]
		var n: float = a.n
		print("%5d  %8.1f %8.1f %8.1f  %5.3f  %7.1f  %8.1f  %6.3f  %9.1f  %9.1f" % [k, a.imep / n, a.bmep / n, a.fmep / n, a.ve / n, a.ca50 / n, a.burn / n, a.lam / n, a.pk / n, a.intake / n])
	quit(0)
