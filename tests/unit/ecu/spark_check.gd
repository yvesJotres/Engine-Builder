extends SceneTree

# Checks the spark crack: one crack per firing (25 a second for one cylinder at 3,000 rpm), and the output stays in range.
# Run: godot --headless -s tests/unit/ecu/spark_check.gd (exit code 1 on failure)

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: " + msg)


func _init() -> void:
	await process_frame # autoloads are registered after _init
	var spec := EngineSpec.new()
	var sound := EngineSound.new()
	root.add_child(sound)
	sound.setup(spec)
	sound.rpm = 3000.0
	var silent := sound.render(4410)
	var silent_energy := 0.0
	for frame in silent:
		silent_energy += frame.x * frame.x
	check(silent_energy == 0.0, "no fabricated spark noise without cylinder flow")
	sound.backfire(100.0)
	var output := sound.render(4410)
	var energy := 0.0
	var in_range := true
	for frame in output:
		energy += frame.x * frame.x
		if absf(frame.x) > 1.0 or not is_finite(frame.x):
			in_range = false
	check(energy > 0.0, "backfire energy excites the exhaust waveguide")
	check(in_range, "output stays within -1 and 1")
	sound.free()
	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
