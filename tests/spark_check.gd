extends SceneTree

# Checks the spark crack: one crack per firing (25 a second for one cylinder at 3,000 rpm), and the output stays in range.
# Run: godot --headless -s tests/spark_check.gd (exit code 1 on failure)

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
	sound.firing = true
	sound.energy = 1.0
	sound.render(4410) # warm up

	var cracks := 0
	var in_range := true
	for i in 44100:
		var before := sound._click_left
		var frame := sound.render(1)
		if before == 0 and sound._click_left > 0:
			cracks += 1
		if absf(frame[0].x) > 1.0:
			in_range = false
	print("cracks in one second at 3000 rpm: %d (expected about 25)" % cracks)
	check(cracks >= 23 and cracks <= 27, "one crack per firing, got %d" % cracks)
	check(in_range, "output stays within -1 and 1")
	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
