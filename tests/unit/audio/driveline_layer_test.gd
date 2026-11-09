extends SceneTree

# The driveline layer: the gear whine follows the rpm, the clutch rattles only at idle in neutral, a gear change clunks once,
# it is silent when the engine is off, and the same inputs give the same output. Exits 1 on any failure.
# Run: godot --headless --path . -s res://tests/unit/audio/driveline_layer_test.gd

const LAYER := preload("res://scripts/audio/layers/driveline_layer.gd")
const RATE := 44100
const BLOCK := 441

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func ctx(rpm: float, gear: int, clutch := 1.0, load := 0.0, speed := 0.0) -> SoundContext:
	var c := SoundContext.new()
	c.running = true
	c.rpm = rpm
	c.gear = gear
	c.clutch_engage = clutch
	c.load = load
	c.speed_ms = speed
	return c


# Renders seconds of audio in engine-sized blocks.
func run(layer, c: SoundContext, seconds: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var total := int(seconds * RATE)
	while out.size() < total:
		out.append_array(layer.render(mini(BLOCK, total - out.size()), c))
	return out


func peak(a: PackedFloat32Array) -> float:
	var p := 0.0
	for x in a:
		p = maxf(p, absf(x))
	return p


func rms(a: PackedFloat32Array) -> float:
	var sum := 0.0
	for x in a:
		sum += x * x
	return sqrt(sum / maxf(a.size(), 1))


# Power of one frequency in a signal, from the Goertzel recurrence.
func power_at(a: PackedFloat32Array, hz: float) -> float:
	var coef := 2.0 * cos(TAU * hz / RATE)
	var s1 := 0.0
	var s2 := 0.0
	for x in a:
		var s0: float = x + coef * s1 - s2
		s2 = s1
		s1 = s0
	return s1 * s1 + s2 * s2 - coef * s1 * s2


func _init() -> void:
	# 1. finite and bounded across neutral, a low gear and a high gear
	var cases := [[900.0, 0], [3000.0, 2], [9000.0, 4]]
	for cs in cases:
		var out := run(LAYER.new(), ctx(cs[0], cs[1], 1.0, 0.8 if cs[1] == 2 else 0.5, 10.0), 2.0)
		var ok := out.size() == 2 * RATE
		for x in out:
			if not is_finite(x) or absf(x) > 0.25:
				ok = false
		check(ok, "rpm %s gear %s: samples finite and under 0.25" % [cs[0], cs[1]])

	# 2. silent when the engine is off
	var off := ctx(3000.0, 2)
	off.running = false
	var quiet := run(LAYER.new(), off, 0.5)
	check(peak(quiet) == 0.0, "silent when not running, peak %s" % peak(quiet))

	# 3. the gear whine sits at rpm / 60 * 17 = 1700 Hz at 6000 rpm
	var whine := run(LAYER.new(), ctx(6000.0, 3, 1.0, 1.0), 1.0)
	var tone := whine.slice(int(0.1 * RATE))
	var p1700 := power_at(tone, 1700.0)
	var p1300 := power_at(tone, 1300.0)
	check(p1700 >= 3.0 * p1300, "whine at 1700 Hz (%s) beats 1300 Hz (%s) by 3x" % [p1700, p1300])

	# 4. the rattle only at idle in neutral
	var idle_neutral := rms(run(LAYER.new(), ctx(1000.0, 0), 2.0))
	var idle_gear := rms(run(LAYER.new(), ctx(1000.0, 3, 1.0, 0.0, 0.0), 2.0))
	var high_neutral := rms(run(LAYER.new(), ctx(3000.0, 0), 2.0))
	check(idle_neutral > idle_gear, "idle rattle in neutral (%s) beats idle in gear (%s)" % [idle_neutral, idle_gear])
	check(high_neutral < idle_neutral, "no rattle at 3000 rpm (%s) vs idle (%s)" % [high_neutral, idle_neutral])

	# 5. one clunk on a gear change, none on the first block
	var shift := LAYER.new()
	var before := run(shift, ctx(3000.0, 2), 0.2)
	var after := run(shift, ctx(3000.0, 3), 0.1)
	var pre := peak(before.slice(before.size() - int(0.1 * RATE)))
	var post := peak(after)
	check(post >= 3.0 * pre, "clunk after the shift (%s) is at least 3x before (%s)" % [post, pre])
	var fresh := run(LAYER.new(), ctx(3000.0, 3), 0.1)
	check(peak(fresh) < 0.1, "a fresh instance does not clunk on its first block, peak %s" % peak(fresh))

	# 6. same inputs, same output
	var seq := [ctx(1000.0, 0), ctx(3000.0, 2, 1.0, 0.8, 10.0), ctx(3000.0, 3, 0.2, 0.5, 8.0)]
	var la = LAYER.new()
	var lb = LAYER.new()
	var a := PackedFloat32Array()
	var b := PackedFloat32Array()
	for c in seq:
		a.append_array(run(la, c, 0.3))
		b.append_array(run(lb, c, 0.3))
	check(a == b, "two fresh instances give identical output")

	print("driveline_layer_test: %s" % ("PASSED" if _fails == 0 else "FAILED"))
	quit(0 if _fails == 0 else 1)
