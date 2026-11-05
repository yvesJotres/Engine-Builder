extends SceneTree

# Checks the exhaust impulse response: it loads, the output stays finite, the level stays close to the dry sound, and
# the render time is printed. Run: godot --headless -s tests/ir_check.gd (exit code 1 on failure)

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: " + msg)


func _init() -> void:
	await process_frame # autoloads are registered after _init
	var spec := EngineSpec.new()
	var sound := EngineSound.new()
	root.add_child(sound) # runs _ready, which loads the response
	sound.setup(spec)
	check(sound._ir.size() > 0, "impulse response loaded")
	var energy := 0.0
	for v in sound._ir:
		energy += v * v
	var expected := EngineSound.IR_LEVEL * EngineSound.IR_LEVEL
	check(absf(energy - expected) < 0.001, "impulse response scaled to the chosen level, got %.4f" % energy)

	sound.rpm = 3000.0
	sound.firing = true
	sound.energy = 1.0
	sound.render(4410) # warm up the pipes
	var start := Time.get_ticks_usec()
	var wet := sound.render(4410)
	var elapsed_ms := (Time.get_ticks_usec() - start) / 1000.0

	var dry_ir := sound._ir
	sound._ir = PackedFloat32Array()
	var dry := sound.render(4410)
	sound._ir = dry_ir

	var rms_wet := _rms(wet)
	var rms_dry := _rms(dry)
	var finite := true
	for frame in wet:
		if is_nan(frame.x) or is_inf(frame.x):
			finite = false
	check(finite, "output is finite")
	check(rms_wet > 0.0, "wet output is not silent")
	var ratio := rms_wet / maxf(rms_dry, 0.000001)
	print("wet/dry level ratio %.3f, render of 0.1 s took %.2f ms" % [ratio, elapsed_ms])
	check(ratio > 0.5 and ratio < 2.0, "level stays close to the dry sound, ratio %.3f" % ratio)
	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)


static func _rms(frames: PackedVector2Array) -> float:
	var sum := 0.0
	for frame in frames:
		sum += frame.x * frame.x
	return sqrt(sum / maxf(frames.size(), 1))
