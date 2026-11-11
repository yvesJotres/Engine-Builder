extends SceneTree

# The exhaust body convolution: it must run at the output rate and use the whole impulse
# response, not an 8 ms slice of it. The native AudioConvolver is checked for correctness
# (delay, gain, long tail) and EngineSound's constants are checked against the IR length.
# Run: godot --headless --path . -s tests/unit/audio/audio_convolver_test.gd

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: " + msg)


func _impulse(n: int, at: int) -> PackedFloat32Array:
	var ir := PackedFloat32Array()
	ir.resize(n)
	if at >= 0 and at < n:
		ir[at] = 1.0
	return ir


func _init() -> void:
	await process_frame
	check(ClassDB.class_exists("AudioConvolver"), "the native AudioConvolver is registered")
	if ClassDB.class_exists("AudioConvolver"):
		var conv: Object = ClassDB.instantiate("AudioConvolver")
		# a unit impulse response passes the signal through
		conv.set_ir(_impulse(64, 0))
		var body := PackedFloat32Array([1.0, 0.5, -0.25, 0.0])
		var dry: PackedFloat32Array = conv.process(body)
		check(dry.size() == body.size(), "the output has the same length as the block")
		check(absf(dry[0] - 1.0) < 1e-6 and absf(dry[1] - 0.5) < 1e-6 and absf(dry[2] + 0.25) < 1e-6,
				"a unit impulse response passes the body through unchanged")
		# a delayed impulse response delays the signal by exactly that many samples
		conv.reset()
		conv.set_ir(_impulse(64, 3))
		var block := PackedFloat32Array()
		block.resize(10)
		block[0] = 1.0
		var out: PackedFloat32Array = conv.process(block)
		check(absf(out[2]) < 1e-6, "nothing comes out before the impulse response delay")
		check(absf(out[3] - 1.0) < 1e-6, "the delayed impulse lands at the right sample")
		# a long tail is actually convolved: energy is still arriving 1,000 samples later
		conv.reset()
		var ir := PackedFloat32Array()
		ir.resize(1152)
		for i in ir.size():
			ir[i] = exp(-float(i) / 256.0) * 0.001
		conv.set_ir(ir)
		check(conv.get_taps() == 1152, "the full 1152-tap kernel is loaded")
		var long_block := PackedFloat32Array()
		long_block.resize(2000)
		long_block[0] = 1.0
		var tail: PackedFloat32Array = conv.process(long_block)
		var late := 0.0
		for i in range(1000, 1200):
			late = maxf(late, absf(tail[i]))
		check(late > 0.0, "the impulse response tail is audible 23 ms after the impulse")

	# the sound must convolve at the output rate, over the whole recording, not an 8 ms slice
	check(is_equal_approx(EngineSound.RATE, 44100.0), "the sound runs at 44.1 kHz")
	var muffled := EngineSound._kernel("res://assets/ir/mild_exhaust.wav")
	check(float(muffled.size()) / EngineSound.RATE >= 0.2,
			"the muffled impulse response is used in full (%.0f ms, not 8 ms)" % (1000.0 * muffled.size() / EngineSound.RATE))
	check(muffled.size() <= EngineSound.MAX_TAPS, "the kernel stays inside MAX_TAPS")
	check(EngineSound.FALLBACK_TAPS > 0, "a GDScript fallback kernel exists for a missing library")

	if _fails == 0:
		print("audio_convolver_test: PASSED")
		quit(0)
	else:
		push_error("audio_convolver_test: %d failures" % _fails)
		quit(1)
