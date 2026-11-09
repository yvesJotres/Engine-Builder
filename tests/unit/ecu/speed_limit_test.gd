extends SceneTree

# The speed limiter closes the throttle at its limit and holds the bike there. It lets go 2 km/h under the limit, so it does not
# chatter. Off, it never touches the throttle. Exits 1 on any failure.
# Run: godot --headless --path . -s res://tests/unit/ecu/speed_limit_test.gd

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func _init() -> void:
	var spec := EngineSpec.new()
	spec.speed_limit_enabled = true
	spec.speed_limit_kmh = 300.0
	var ecu := ECU.new()
	var kmh := func(v: float) -> float: return v / 3.6
	# below the limit: the rider's throttle passes through
	check(ecu.update(0.001, 9000.0, 1.0, true, spec, kmh.call(250.0), 0.0, 4) < 0.0, "under the limit the throttle is not overridden")
	# at the limit: the throttle closes
	check(ecu.update(0.001, 14000.0, 1.0, true, spec, kmh.call(300.5), 0.0, 4) == 0.0, "at the limit the throttle closes")
	# just under the limit but inside the 2 km/h band: still held
	check(ecu.update(0.001, 14000.0, 1.0, true, spec, kmh.call(299.0), 0.0, 4) == 0.0, "inside the band it stays closed")
	# under the band: it lets go
	check(ecu.update(0.001, 14000.0, 1.0, true, spec, kmh.call(297.0), 0.0, 4) < 0.0, "under the band it lets go")
	# switched off: no override, even over the limit
	spec.speed_limit_enabled = false
	check(ecu.update(0.001, 14000.0, 1.0, true, spec, kmh.call(310.0), 0.0, 4) < 0.0, "off, the throttle is never overridden")
	print("speed_limit_test: %s" % ("PASSED" if _fails == 0 else "FAILED"))
	quit(0 if _fails == 0 else 1)
