extends SceneTree

# A bike with the hardware but no published launch figures must still launch. The CBR1000RR-R's Start Mode has no
# factory rpm/throttle/speed numbers, so it falls back to EngineSpec's defaults - and a zero target would have made the
# arm condition rpm < 0 * 1.1 impossible, leaving the aid fitted but dead.
# Run: godot --headless --path . -s tests/unit/ecu/launch_defaults_test.gd (prints PASS or FAIL)

var _fails := 0


func _init() -> void:
	await process_frame

	var spec := EngineSpec.new()
	spec.launch_control = true
	spec.redline_rpm = 15000.0
	# nothing else set: no launch_rpm, throttle or speed of its own
	var ecu := ECU.new()
	var throttle := ecu.update(0.016, 3000.0, 1.0, true, spec, 0.0, 0.8, 1)
	check(ecu.is_launch_active(), "Start Mode arms on a spec that never stated a launch rpm")
	check(ecu.get_launch_target_rpm() > 1000.0,
		"the target is a real rpm, not zero (%.0f)" % ecu.get_launch_target_rpm())
	check(ecu.get_launch_target_rpm() < spec.redline_rpm,
		"and it sits under the redline (%.0f)" % ecu.get_launch_target_rpm())
	check(throttle > 0.0, "and the ECU asks for throttle (%.2f)" % throttle)

	# the same bike with the launch switched off must not arm, whatever the defaults say
	var off := EngineSpec.new()
	off.launch_control = false
	var ecu_off := ECU.new()
	ecu_off.update(0.016, 3000.0, 1.0, true, off, 0.0, 0.8, 1)
	check(not ecu_off.is_launch_active(), "with the aid off nothing arms")

	print("RESULT: " + ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(1 if _fails > 0 else 0)


func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1
