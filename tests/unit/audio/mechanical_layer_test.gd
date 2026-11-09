extends SceneTree

# The mechanical layer: finite and bounded, silent when stopped, rumble and whine rise with rpm, the whine sits on the gear mesh
# frequency, and two instances render the same. Exits 1 on any failure.
# Run: godot --headless --path . -s res://tests/unit/audio/mechanical_layer_test.gd

const LAYER := preload("res://scripts/audio/layers/mechanical_layer.gd")
const CTX := preload("res://scripts/audio/layers/sound_context.gd")
const RATE_HZ := 44100.0
const BLOCK := 441

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func _ctx(rpm: float, load: float = 0.5, running: bool = true) -> Variant:
	var c = CTX.new()
	c.rpm = rpm
	c.load = load
	c.running = running
	c.primary_ratio = 1.0
	return c


# Renders total samples in blocks of BLOCK frames, the way the engine calls a layer.
func _render(layer: Variant, c: Variant, total: int) -> PackedFloat32Array:
	var all := PackedFloat32Array()
	all.resize(total)
	var pos := 0
	while pos < total:
		var n := mini(BLOCK, total - pos)
		var block: PackedFloat32Array = layer.render(n, c)
		for i in n:
			all[pos + i] = block[i]
		pos += n
	return all


func _rms(x: PackedFloat32Array) -> float:
	var sum := 0.0
	for v in x:
		sum += v * v
	return sqrt(sum / maxf(1.0, float(x.size())))


# Goertzel power of x at frequency f: the power of one bin, no FFT needed.
func _goertzel(x: PackedFloat32Array, f: float) -> float:
	var coeff := 2.0 * cos(TAU * f / RATE_HZ)
	var s1 := 0.0
	var s2 := 0.0
	for v in x:
		var s0 := float(v) + coeff * s1 - s2
		s2 = s1
		s1 = s0
	return s1 * s1 + s2 * s2 - coeff * s1 * s2


func _init() -> void:
	# 1. finite and bounded across a rpm sweep, on one continuous instance
	var sweep: Variant = LAYER.new()
	var bounded := true
	var finite := true
	for rpm in [600.0, 1500.0, 4000.0, 9000.0, 14000.0]:
		var x := _render(sweep, _ctx(rpm), int(2.0 * RATE_HZ))
		for v in x:
			if not is_finite(v):
				finite = false
			if absf(v) > 0.25:
				bounded = false
	check(finite, "every sample is finite across the sweep")
	check(bounded, "every sample is within |x| <= 0.25 across the sweep")

	# 2. silent when the engine is not running
	var off: Variant = LAYER.new()
	var off_out := _render(off, _ctx(6000.0, 0.5, false), int(RATE_HZ))
	var all_zero := true
	for v in off_out:
		if v != 0.0:
			all_zero = false
	check(all_zero, "all samples are exactly 0.0 when not running")

	# 3. the rms rises with rpm
	var low: Variant = LAYER.new()
	var high: Variant = LAYER.new()
	var rms_low := _rms(_render(low, _ctx(1500.0), int(2.0 * RATE_HZ)))
	var rms_high := _rms(_render(high, _ctx(9000.0), int(2.0 * RATE_HZ)))
	check(rms_high > rms_low, "rms at 9000 rpm (%f) is above rms at 1500 rpm (%f)" % [rms_high, rms_low])

	# 4. the whine sits on 2300 Hz at 6000 rpm (23 teeth), not 1900 Hz
	var tone: Variant = LAYER.new()
	var warm := int(0.2 * RATE_HZ)
	var seg := _render(tone, _ctx(6000.0), warm + int(RATE_HZ)).slice(warm)
	var p_mesh := _goertzel(seg, 2300.0)
	var p_off := _goertzel(seg, 1900.0)
	check(p_mesh >= 3.0 * p_off, "2300 Hz power (%f) is at least 3x the 1900 Hz power (%f)" % [p_mesh, p_off])

	# 5. two fresh instances with the same context render the same samples
	var a: Variant = LAYER.new()
	var b: Variant = LAYER.new()
	var ra := _render(a, _ctx(6000.0), int(RATE_HZ))
	var rb := _render(b, _ctx(6000.0), int(RATE_HZ))
	check(ra == rb, "two fresh instances render identical samples")

	print("mechanical_layer_test: %s" % ("PASSED" if _fails == 0 else "FAILED"))
	quit(0 if _fails == 0 else 1)
