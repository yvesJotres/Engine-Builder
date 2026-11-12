extends SceneTree

# Backpressure has to come out of the pipe's geometry: quadratic in flow, falling with gas temperature, higher through a
# narrower tailpipe. The last check is the point of the whole thing - the engine must lose torque when the pipe restricts.
# Run: godot --headless --path . --quit-after 3000 -s res://tests/unit/exhaust/backpressure_test.gd

const DT := 1.0 / 60.0

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func _spec() -> EngineSpec:
	var spec := EngineSpec.new()
	for key in Presets.PRESETS["honda_cbr1000rrr_sp"].keys():
		spec.set(key, Presets.PRESETS["honda_cbr1000rrr_sp"][key])
	return spec


func _init() -> void:
	var spec := _spec()
	var layout := ExhaustLayout.build(spec)
	print("layout: %d pipes, %.2f m of pipe" % [layout.pipes.size(), layout.total_length_m()])

	# no flow, no backpressure
	check(Backpressure.mean_gauge_pa(layout, 0.0, 900.0) == 0.0, "a stopped engine has no backpressure")

	# quadratic in flow (friction and minor losses are both rho v^2 / 2)
	var low := Backpressure.mean_gauge_pa(layout, 0.05, 900.0)
	var double_low := Backpressure.mean_gauge_pa(layout, 0.10, 900.0)
	print("0.05 kg/s -> %.0f Pa, 0.10 kg/s -> %.0f Pa (ratio %.2f)" % [low, double_low, double_low / maxf(low, 1.0e-9)])
	check(absf(double_low / low - 4.0) < 0.05, "doubling the flow quadruples the pressure (%.2f)" % (double_low / low))

	# at a FIXED mass flow the hotter gas is thinner, so it has to travel faster and loses MORE pressure (v = mdot/(rho*A))
	var cold := Backpressure.mean_gauge_pa(layout, 0.1, 700.0)
	var hot := Backpressure.mean_gauge_pa(layout, 0.1, 1400.0)
	print("0.10 kg/s at 700 K -> %.0f Pa, at 1400 K -> %.0f Pa" % [cold, hot])
	check(hot > cold, "a hotter pipe resists the same mass flow more (%.0f > %.0f)" % [hot, cold])
	check(absf(hot / cold - 2.0) < 0.05, "and it scales with the temperature (%.2f)" % (hot / cold))

	# a pinched tailpipe restricts more: take 30 % off every radius downstream of the collector
	var pinched := ExhaustLayout.build(spec)
	for pipe in pinched.pipes:
		if pipe.kind == "tail" or pipe.kind == "muffler":
			for i in pipe.radii.size():
				pipe.radii[i] *= 0.7
	var open_bp := Backpressure.mean_gauge_pa(layout, 0.12, 1100.0)
	var pinched_bp := Backpressure.mean_gauge_pa(pinched, 0.12, 1100.0)
	print("0.12 kg/s at 1100 K: open %.0f Pa, pinched %.0f Pa" % [open_bp, pinched_bp])
	check(pinched_bp > open_bp, "a narrower tailpipe raises it (%.0f > %.0f)" % [pinched_bp, open_bp])

	# the engine feels it: the live path must not be at atmosphere any more
	var sim := EngineSim.new()
	sim.audio_enabled = false
	sim.set_audio_layout(layout, spec.cylinders)
	for i in 240:
		sim.step(DT, spec, 0.0, true, i < 60, false, false, 1.0)
	var idle_bp := sim.backpressure_pa() - Cylinder.P0
	for i in 600:
		sim.step(DT, spec, 1.0, true, false, false, false, 1.0)
	var wot_bp := sim.backpressure_pa() - Cylinder.P0
	print("engine, live path: idle %.0f Pa gauge (%.0f rpm), wide open %.0f Pa gauge (%.0f rpm)"
		% [idle_bp, 1200.0, wot_bp, sim.rpm])
	check(idle_bp > 0.0, "the engine breathes against a real pressure at idle (%.0f Pa)" % idle_bp)
	check(wot_bp > idle_bp, "and a higher one wide open (%.0f > %.0f Pa)" % [wot_bp, idle_bp])
	check(wot_bp < 40000.0, "wide-open backpressure is in the range a motorcycle exhaust really has, not double atmosphere (%.0f Pa)" % wot_bp)

	print("backpressure_test: %s" % ("PASS" if _fails == 0 else "FAIL"))
	quit(0 if _fails == 0 else 1)
