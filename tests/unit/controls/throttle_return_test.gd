extends SceneTree

# The throttle springs shut at a measured speed, not a guessed one. A real grip's return was timed at 0.075 s from
# the hand letting go to the clank of the tube hitting its closed stop (a 10 fps phone clip, with the impact timed
# from the audio track where it resolves to under a millisecond). THROTTLE_RETURN_SPEED is full travel per second, so
# that measurement is 1 / 0.075 = 13.3.
#
# This test drives the real _process spring with a fixed step, so it fails if the constant is retuned, if the spring is
# bypassed, or if a clamp stops the throttle short of fully closed.
# Run: godot --headless --path . -s res://tests/unit/controls/throttle_return_test.gd (prints PASS or FAIL)

const MEASURED_RETURN_S := 0.075
const TOLERANCE_S := 0.010

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func _init() -> void:
	await process_frame
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 4:
		await process_frame

	# the constant has to encode the measurement
	var from_const: float = 1.0 / main.THROTTLE_RETURN_SPEED
	check(abs(from_const - MEASURED_RETURN_S) < 0.005,
		"THROTTLE_RETURN_SPEED encodes 0.075 s (got %.3f s from %.2f/s)" % [from_const, main.THROTTLE_RETURN_SPEED])

	# the spring itself, stepped by hand so no real time or input is involved
	var dt := 1.0 / 120.0
	main._throttle = 1.0
	var t := 0.0
	while main._throttle > 0.0 and t < 1.0:
		main._process(dt)
		t += dt
	check(main._throttle == 0.0, "the throttle closes fully (left at %.4f after %.3f s)" % [main._throttle, t])
	check(abs(t - MEASURED_RETURN_S) < TOLERANCE_S,
		"full travel closes in %.3f s, measured %.3f s" % [t, MEASURED_RETURN_S])
	check(t < 1.0 / 3.0, "the return is quicker than the old 3.0/s guess (0.333 s); got %.3f s" % t)

	if _fails == 0:
		print("throttle_return_test: PASS (%.3f s to close from full)" % t)
	quit(0 if _fails == 0 else 1)
