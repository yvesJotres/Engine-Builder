extends SceneTree

# Asserting checks for the ECU and the idle valve returns to neutral after a stall, the trims stay
# inside their limits, and the spark advance keeps the burn centre at its target and never falls as rpm rises.
# Run: godot --headless -s tests/ecu_test.gd (exit code 1 on any failure)

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: " + msg)


func _init() -> void:
	await process_frame # class names are ready after the first frame
	var dt := 1.0 / 3600.0

	# 1. Drive the ECU hard (rpm far above the target) so the idle valve closes, then stall it and restart.
	var ecu := ECU.new()
	ecu.target_rpm = 1200.0
	for i in int(20.0 / dt):
		ecu.update(dt, 3000.0, 0.0, true) # idling far too fast for 20 s
	check(ecu.air_factor() < 0.2, "the idle valve closes when the engine idles too fast, got %.3f" % ecu.air_factor())
	check(ecu.trim >= ECU.TRIM_MIN and ecu.trim <= ECU.TRIM_MAX, "spark trim stays inside its limits, got %.2f" % ecu.trim)
	for i in int(4.0 / dt):
		ecu.update(dt, 0.0, 0.0, false) # the engine stalls
	check(absf(ecu.air_factor() - 1.0) < 0.05, "the idle valve returns to neutral after a stall, got %.3f" % ecu.air_factor())
	check(absf(ecu.trim) < 0.05, "spark trim returns to zero after a stall, got %.3f" % ecu.trim)

	# 2. Off the idle (throttle open) the ECU lets go too.
	for i in int(20.0 / dt):
		ecu.update(dt, 3000.0, 0.0, true)
	for i in int(4.0 / dt):
		ecu.update(dt, 5000.0, 0.5, true) # throttle open
	check(absf(ecu.air_factor() - 1.0) < 0.05, "the idle valve returns to neutral with the throttle open, got %.3f" % ecu.air_factor())

	# 3. Below the active speed (just under the firing speed) the ECU stays out of the way.
	var starting := ECU.new()
	for i in int(2.0 / dt):
		starting.update(dt, 200.0, 0.0, true)
	check(starting.trim == 0.0 and starting.air_factor() == 1.0, "no ECU action below the active rpm")

	# 4. The spark advance keeps the burn centre (50% burnt) at the target after TDC at every speed, and never falls as rpm rises.
	var last := -1.0
	var monotonic := true
	var centred := true
	for rpm in range(0, 15001, 250):
		var advance := EngineAir.spark_advance_deg(float(rpm))
		if advance < last:
			monotonic = false
		last = advance
		var ca50 := Cylinder.burn_duration_deg(float(rpm)) * Cylinder.WIEBE_CA50 - advance
		if absf(ca50 - Cylinder.CA50_TARGET) > 0.01:
			centred = false
	check(centred, "the burn centre sits at the target after TDC at every speed")
	check(monotonic, "the spark advance never falls as rpm rises")
	check(EngineAir.spark_advance_deg(1200.0) > 5.0 and EngineAir.spark_advance_deg(1200.0) < 25.0, "idle advance is in a sane range, got %.1f" % EngineAir.spark_advance_deg(1200.0))

	# 5. A just-fired engine, well below the idle target, gets the start boost: the valve opens wide at once.
	var fired := ECU.new()
	fired.target_rpm = 1200.0
	for i in int(0.5 / dt):
		fired.update(dt, 500.0, 0.0, true)
	check(fired.air_factor() > 3.0, "a just-fired engine gets the start air boost, got x%.2f" % fired.air_factor())

	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
