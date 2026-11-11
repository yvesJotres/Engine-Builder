extends SceneTree

# Clutch slip is engine rpm minus the rpm the wheel drives through the gear. Run:
# godot --headless --path . -s tests/unit/dyno/dyno_slip_test.gd

var _fails := 0


func _init() -> void:
	# 2 m/s over a 0.5 m wheel is 4 rad/s. Ratio 10 gives 40 rad/s at the crank, which is 382.17 rpm.
	var wheel_rpm := 2.0 / 0.5 * 10.0 * 60.0 / TAU
	check(absf(DynoTest.slip_rpm(wheel_rpm, 2.0, 10.0, 0.5)) < 1e-6, "a locked clutch has no slip")
	check(absf(DynoTest.slip_rpm(wheel_rpm + 150.0, 2.0, 10.0, 0.5) - 150.0) < 1e-6, "engine above wheel speed reads positive slip")
	check(absf(DynoTest.slip_rpm(wheel_rpm - 40.0, 2.0, 10.0, 0.5) + 40.0) < 1e-6, "engine below wheel speed reads negative slip")
	check(is_nan(DynoTest.slip_rpm(5000.0, 2.0, 0.0, 0.5)), "zero drive ratio gives no slip reading")
	check(is_nan(DynoTest.slip_rpm(5000.0, 2.0, 10.0, 0.0)), "zero wheel radius gives no slip reading")
	check(absf(DynoTest.slip_rpm(0.0, 0.0, 10.0, 0.5)) < 1e-9, "stationary bike at idle rpm has no slip")
	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)


func check(ok: bool, message: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: " + message)
	else:
		print("PASS: " + message)
