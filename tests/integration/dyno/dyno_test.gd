extends SceneTree

# Runs the automatic dyno test on the default engine with the real physics and no scene. Checks that it starts the engine,
# runs every gear to its end, records a curve, and that the peaks are in a plausible range for the CBR150R.
# Run: godot --headless -s tests/integration/dyno/dyno_test.gd (exit code 1 on failure)

var _fails := 0


func check(ok: bool, msg: String) -> void:
	print(("ok   " if ok else "FAIL ") + msg)
	if not ok:
		_fails += 1


func _init() -> void:
	var spec := EngineSpec.new()
	# Apply CBR150R preset to get proper wheel radius and other params
	var preset: Dictionary = Presets.PRESETS["honda_cbr150r"]
	if preset:
		for key in preset:
			spec.set(key, preset[key])
	var sim := EngineSim.new()
	sim.audio_enabled = false
	sim.physics_dt = 1.0 / 1200.0 # a faster step than the game's default, enough for a flow check
	var dyno := DynoTest.new()
	dyno.start(spec, sim)
	var frame := 1.0 / 60.0
	var frames := 0
	while dyno.active() and frames < 60 * 900:
		dyno.advance(frame, sim, spec, 1.0, true)
		frames += 1
	var r := dyno.result()
	print("finished after %.0f s of simulated time: %s" % [frames * frame, dyno.status])
	check(dyno.phase == DynoTest.Phase.DONE, "the test runs to its end")
	check(dyno.ok, "the test finished without a fault")
	check(r.curve.size() > 20, "the curve has points across the rev range (%d)" % r.curve.size())
	var first: Dictionary = r.curve[0]
	check(float(first.rpm) < 3000.0, "the pull is recorded from near idle (%.0f rpm)" % float(first.rpm))
	var pt: Dictionary = r.peak_torque
	var ph: Dictionary = r.peak_hp
	print("peak torque %.2f N·m at %.0f rpm, peak power %.2f hp at %.0f rpm" % [pt.torque, pt.rpm, ph.hp, ph.rpm])
	check(pt.torque > 8.0 and pt.torque < 20.0, "peak torque is plausible for a 150 cc single (%.1f N·m)" % pt.torque)
	check(ph.hp > 8.0 and ph.hp < 25.0, "peak power is plausible for a 150 cc single (%.1f hp)" % ph.hp)
	check(ph.rpm > pt.rpm, "peak power comes at a higher rpm than peak torque")
	var factor: float = r.sae_factor
	check(factor > 0.9 and factor < 1.05, "SAE J1349 factor is %.3f" % factor)
	check(is_equal_approx(float(ph.corrected), ph.hp * factor), "corrected power is the measured power times the factor")
	check(float(r.curve[0].bsfc_g_kwh) > 0.0, "the first point carries a BSFC (%.0f g/kWh)" % float(r.curve[0].bsfc_g_kwh))
	check(float(pt.stdev) >= 0.0, "the torque peak has a spread (%.2f N·m)" % float(pt.stdev))
	var worst := 0.0
	var worst_rpm := 0.0
	for i in range(1, r.curve.size()):
		var earlier: Dictionary = r.curve[i - 1]
		var later: Dictionary = r.curve[i]
		if float(later.rpm) - float(earlier.rpm) < 400.0:
			var step: float = absf(float(later.torque) - float(earlier.torque))
			if step > worst:
				worst = step
				worst_rpm = float(later.rpm)
	check(worst < 4.0, "the curve steps by at most 4 N·m between neighbouring points (%.1f at %.0f rpm)" % [worst, worst_rpm])
	var gears_run := 0
	for g in r.gears:
		print("gear %d: %.0f samples, peak %.2f N·m at %.0f rpm, %.2f hp at %.0f rpm, %.0f km/h" % [g.gear, g.samples, g.torque, g.torque_rpm, g.hp, g.hp_rpm, g.kmh])
		if g.samples > 0.0:
			gears_run += 1
			check(float(g.kmh) > 5.0, "gear %d reached a road speed (%.0f km/h)" % [g.gear, g.kmh])
	check(gears_run >= 4, "readings were taken in at least four gears (%d)" % gears_run)
	check(float(r.gears[gears_run - 1].kmh) > float(r.gears[0].kmh), "a higher gear is faster than first (%.0f vs %.0f km/h)" % [r.gears[gears_run - 1].kmh, r.gears[0].kmh])
	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
