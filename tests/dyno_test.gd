extends SceneTree

# Runs the automatic dyno test on the default engine with the real physics and no scene. Checks that it starts the engine,
# runs every gear to its end, records a curve, and that the peaks are in a plausible range for the CBR150R.
# Run: godot --headless -s tests/dyno_test.gd (exit code 1 on failure)

var _fails := 0


func check(ok: bool, msg: String) -> void:
	print(("ok   " if ok else "FAIL ") + msg)
	if not ok:
		_fails += 1


func _init() -> void:
	var spec := EngineSpec.new()
	var sim := EngineSim.new()
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
	var pt: Dictionary = r.peak_torque
	var ph: Dictionary = r.peak_hp
	print("peak torque %.2f N·m at %.0f rpm, peak power %.2f hp at %.0f rpm" % [pt.torque, pt.rpm, ph.hp, ph.rpm])
	check(pt.torque > 8.0 and pt.torque < 20.0, "peak torque is plausible for a 150 cc single (%.1f N·m)" % pt.torque)
	check(ph.hp > 8.0 and ph.hp < 25.0, "peak power is plausible for a 150 cc single (%.1f hp)" % ph.hp)
	check(ph.rpm > pt.rpm, "peak power comes at a higher rpm than peak torque")
	var gears_run := 0
	for g in r.gears:
		print("gear %d: %.0f samples, peak %.2f N·m at %.0f rpm, %.2f hp at %.0f rpm" % [g.gear, g.samples, g.torque, g.torque_rpm, g.hp, g.hp_rpm])
		if g.samples > 0.0:
			gears_run += 1
	check(gears_run >= 4, "readings were taken in at least four gears (%d)" % gears_run)
	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
