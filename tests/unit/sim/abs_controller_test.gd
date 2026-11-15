extends SceneTree

# The controller is a state machine on slip: over the target it releases pressure fast, under the re-apply point it
# builds pressure slowly, and between the two it holds. Release must always be faster than apply - that asymmetry is
# what stops a real ABS re-locking the wheel on every cycle.
# Run: godot --headless --path . -s tests/unit/sim/abs_controller_test.gd

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func _init() -> void:
	await process_frame
	var abs := AbsController.new()
	abs.configure(0.12, 8.0, 7.0)
	var capacity := 700.0
	# under the target: it keeps building pressure, but no faster than the apply slew
	var torque := 0.0
	for i in 30:
		torque = abs.step(1.0 / 60.0, -0.05, 30.0, torque, capacity)
	check(torque > 0.0, "below the slip target the controller applies torque")
	check(torque <= AbsController.APPLY_SLEW / 60.0 * 31 + 1.0, "and no faster than the apply slew")
	# over the target: it dumps pressure much faster than it built it
	var released := torque
	for i in 10:
		released = abs.step(1.0 / 60.0, -0.40, 30.0, released, capacity)
	check(released < torque * 0.5, "over the target it releases fast (%.0f -> %.0f N·m)" % [torque, released])
	check(abs.cycles > 0, "a release counts as a cycle for the HUD")
	# below the cutoff it hands the brake back
	var slow := AbsController.new()
	slow.configure(0.12, 8.0, 7.0)
	var low := 0.0
	for i in 20:
		low = slow.step(1.0 / 60.0, -0.90, 1.0, low, capacity) # 1 m/s = 3.6 km/h
	check(low > capacity * 0.9, "under the cutoff speed the rider's lever goes straight through (%.0f N·m)" % low)
	check(not slow.active, "and the controller reports itself inactive")
	print("ABS: %d cycles, %.0f N·m out at 40%% slip" % [abs.cycles, released])
	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
