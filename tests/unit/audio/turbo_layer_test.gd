extends SceneTree

# The turbo layer: silent when it should be, the whistle follows boost, a lift fires one blow-off, and renders repeat.
# Exits 1 on any failure.
# Run: godot --headless --path . -s res://tests/unit/audio/turbo_layer_test.gd

const LAYER := preload("res://scripts/audio/layers/turbo_layer.gd")
const BLOCK := 441

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func ctx(rpm: float, throttle: float, boost: float, turbo: bool, running: bool) -> SoundContext:
	var c := SoundContext.new()
	c.rpm = rpm
	c.throttle = throttle
	c.boost_ratio = boost
	c.turbo = turbo
	c.running = running
	return c


# Renders seconds of audio in engine-sized blocks with one context.
func render(layer: SoundLayer, seconds: float, c: SoundContext) -> PackedFloat32Array:
	var total := int(seconds * SoundLayer.RATE)
	var out := PackedFloat32Array()
	var done := 0
	while done < total:
		var n := mini(BLOCK, total - done)
		out.append_array(layer.render(n, c))
		done += n
	return out


func peak(s: PackedFloat32Array) -> float:
	var m := 0.0
	for i in s.size():
		m = maxf(m, absf(s[i]))
	return m


func rms(s: PackedFloat32Array) -> float:
	var sum := 0.0
	for i in s.size():
		sum += s[i] * s[i]
	return sqrt(sum / maxf(float(s.size()), 1.0))


# Goertzel power at one frequency over the whole buffer.
func goertzel(s: PackedFloat32Array, hz: float) -> float:
	var coeff := 2.0 * cos(2.0 * PI * hz / SoundLayer.RATE)
	var s1 := 0.0
	var s2 := 0.0
	for i in s.size():
		var s0: float = s[i] + coeff * s1 - s2
		s2 = s1
		s1 = s0
	return s1 * s1 + s2 * s2 - coeff * s1 * s2


# The vibrato spreads the tone into sidebands 5 Hz apart, so a tone's power is the sum over that comb.
func comb_power(s: PackedFloat32Array, center: float) -> float:
	var total := 0.0
	for k in range(-20, 21):
		total += goertzel(s, center + 5.0 * k)
	return total


# Turbo on, boost 1.6: full throttle, then a lift, then a second lift 0.21 s after the first.
func lift_sequence(layer: SoundLayer) -> Array:
	var c := ctx(6000.0, 1.0, 1.6, true, true)
	render(layer, 1.5, c) # let the spool settle so the lift is the only change
	var pre := render(layer, 0.3, c)
	c.throttle = 0.0
	var post := render(layer, 0.2, c)
	c.throttle = 1.0
	render(layer, 0.01, c)
	c.throttle = 0.0
	var second := render(layer, 0.2, c)
	return [pre, post, second]


func _init() -> void:
	# 1. silent when it should be
	var off: SoundLayer = LAYER.new()
	check(peak(render(off, 0.2, ctx(6000.0, 0.5, 1.8, false, true))) == 0.0, "zeros when turbo is false")
	var stopped: SoundLayer = LAYER.new()
	check(peak(render(stopped, 0.2, ctx(6000.0, 0.5, 1.8, true, false))) == 0.0, "zeros when the engine is not running")

	# 2. finite and bounded over 3 s of boost
	var run: SoundLayer = LAYER.new()
	var all := render(run, 3.0, ctx(6000.0, 0.5, 1.8, true, true))
	var finite := true
	for i in all.size():
		if not is_finite(all[i]):
			finite = false
	check(finite, "every sample is finite")
	check(peak(all) <= 0.25, "peak stays under 0.25, got %f" % peak(all))

	# 3. the whistle follows boost, and there is none without it
	var whistle: SoundLayer = LAYER.new()
	var w := render(whistle, 2.0, ctx(6000.0, 0.5, 1.8, true, true))
	var tail := w.slice(44100)
	var tone := comb_power(tail, 7500.0)
	var low := comb_power(tail, 3000.0)
	check(tone >= 3.0 * low, "7500 Hz power %s should be 3x the 3000 Hz power %s" % [str(tone), str(low)])
	var flat: SoundLayer = LAYER.new()
	check(rms(render(flat, 1.0, ctx(6000.0, 0.5, 1.0, true, true))) < 0.005, "quiet at no boost")

	# 4. a lift fires one blow-off, and a second lift inside the cooldown does not
	var bo: SoundLayer = LAYER.new()
	var seqs := lift_sequence(bo)
	var pre_seg: PackedFloat32Array = seqs[0]
	var post_seg: PackedFloat32Array = seqs[1]
	var second_seg: PackedFloat32Array = seqs[2]
	check(rms(post_seg) > rms(pre_seg), "rms after the lift %f is above before %f" % [rms(post_seg), rms(pre_seg)])
	check(rms(second_seg) < rms(post_seg), "a second lift adds no burst: %f is below %f" % [rms(second_seg), rms(post_seg)])

	# 5. repeatable: two fresh instances give identical output
	var a: SoundLayer = LAYER.new()
	var b: SoundLayer = LAYER.new()
	var ra := lift_sequence(a)
	var rb := lift_sequence(b)
	check(ra[0] == rb[0] and ra[1] == rb[1] and ra[2] == rb[2], "two instances render the same samples")

	print("turbo_layer_test: %s" % ("PASSED" if _fails == 0 else "FAILED"))
	quit(0 if _fails == 0 else 1)
