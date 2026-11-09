extends SceneTree

# The knock layer rings once per new knock, high and short, stays silent otherwise, caps a burst at four pings and stays
# quiet while the engine is off. Exits 1 on any failure.
# Run: godot --headless --path . -s res://tests/unit/audio/knock_layer_test.gd

const LAYER := preload("res://scripts/audio/layers/knock_layer.gd")
const CONTEXT := preload("res://scripts/audio/layers/sound_context.gd")
const RATE := 44100.0

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func make_ctx(count: int) -> RefCounted:
	var c = CONTEXT.new()
	c.rpm = 6000.0
	c.running = true
	c.knock_count = count
	return c


func peak(x: PackedFloat32Array, from: int, to: int) -> float:
	var p := 0.0
	for i in range(from, to):
		p = maxf(p, absf(x[i]))
	return p


func rms(x: PackedFloat32Array, from: int, to: int) -> float:
	var s := 0.0
	for i in range(from, to):
		s += x[i] * x[i]
	return sqrt(s / float(to - from))


# Power of one frequency in a signal, from the Goertzel recurrence.
func goertzel(x: PackedFloat32Array, freq: float) -> float:
	var coeff := 2.0 * cos(TAU * freq / RATE)
	var s1 := 0.0
	var s2 := 0.0
	for v in x:
		var s: float = v + coeff * s1 - s2
		s2 = s1
		s1 = s
	return s1 * s1 + s2 * s2 - coeff * s1 * s2


func _init() -> void:
	# 1. silent while the count does not change
	var layer = LAYER.new()
	var out = layer.render(44100, make_ctx(0))
	check(peak(out, 0, out.size()) == 0.0, "silent with no knock over one second")

	# 2. a starting count above zero is adopted, not played
	layer = LAYER.new()
	out = layer.render(1000, make_ctx(5))
	check(peak(out, 0, out.size()) == 0.0, "a starting knock_count of 5 does not ping")

	# 3. one knock: a ping that decays
	layer = LAYER.new()
	layer.render(512, make_ctx(5))
	out = layer.render(4410, make_ctx(6))
	var p30 := peak(out, 0, 1323)
	check(p30 >= 0.05 and p30 <= 0.2 + 1e-6, "ping peak within 30 ms is 0.05..0.2, got %f" % p30)
	var first := rms(out, 0, 882)
	var last := rms(out, 3528, 4410)
	check(last < 0.1 * first, "ping decays: last 20 ms rms %f < 10%% of first %f" % [last, first])

	# 4. the ping is high-pitched
	var head: PackedFloat32Array = out.slice(0, 1323)
	var p_high := maxf(goertzel(head, 6000.0), maxf(goertzel(head, 5600.0), goertzel(head, 6400.0)))
	var p_low := goertzel(head, 1000.0)
	check(p_high >= 5.0 * p_low, "6 kHz power %f is at least 5x the 1 kHz power %f" % [p_high, p_low])

	# 5. a jump of 10 gives at most 4 pings: the output matches a jump of 4 exactly
	layer = LAYER.new()
	layer.render(512, make_ctx(5))
	var jump10: PackedFloat32Array = layer.render(4410, make_ctx(15))
	var jump4_layer = LAYER.new()
	jump4_layer.render(512, make_ctx(5))
	var jump4: PackedFloat32Array = jump4_layer.render(4410, make_ctx(9))
	check(jump10 == jump4, "a jump of 10 renders the same as a jump of 4")
	check(peak(jump10, 0, jump10.size()) <= 0.2 + 1e-6, "burst peak stays at or below 0.2")

	# 6. engine off: silent even when knocks happen, and no late ping after it restarts
	layer = LAYER.new()
	layer.render(512, make_ctx(5))
	var off = make_ctx(7)
	off.running = false
	out = layer.render(2000, off)
	check(peak(out, 0, out.size()) == 0.0, "silent while not running, even with a new knock")
	out = layer.render(4410, make_ctx(7))
	check(peak(out, 0, out.size()) == 0.0, "no late ping after running resumes")

	# 7. repeatable: two fresh instances give the same output
	var a = LAYER.new()
	var b = LAYER.new()
	var oa := PackedFloat32Array()
	var ob := PackedFloat32Array()
	for n in [5, 6, 8, 9, 9, 12]:
		oa.append_array(a.render(2000, make_ctx(n)))
		ob.append_array(b.render(2000, make_ctx(n)))
	check(oa == ob, "two instances with the same sequence render identically")

	print("knock_layer_test: %s" % ("PASSED" if _fails == 0 else "FAILED"))
	quit(0 if _fails == 0 else 1)
