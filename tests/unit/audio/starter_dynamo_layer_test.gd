extends SceneTree

# Starter and dynamo layers: the alternator tone follows its pole count and drive ratio, the starter is silent
# when released, and both stay finite. Exits 1 on any failure.

const STARTER := preload("res://scripts/audio/layers/starter_layer.gd")
const DYNAMO := preload("res://scripts/audio/layers/dynamo_layer.gd")
const RATE := 44100.0
const BLOCK := 441

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func goertzel(x: PackedFloat32Array, hz: float) -> float:
	var coeff := 2.0 * cos(TAU * hz / RATE)
	var s1 := 0.0
	var s2 := 0.0
	for v in x:
		var s: float = v + coeff * s1 - s2
		s2 = s1
		s1 = s
	return s1 * s1 + s2 * s2 - coeff * s1 * s2


func render(layer: SoundLayer, frames: int, c: SoundContext) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	while out.size() < frames:
		var n := mini(BLOCK, frames - out.size())
		out.append_array(layer.render(n, c))
	return out


func ctx(rpm: float, starter: float, running := true) -> SoundContext:
	var c := SoundContext.new()
	c.rpm = rpm
	c.starter = starter
	c.running = running
	c.cylinders = 4
	c.four_stroke = true
	c.fire_time = 5.0
	return c


func _init() -> void:
	var spec := EngineSpec.new()
	spec.alternator_drive_ratio = 1.0
	spec.alternator_poles = 12
	var dynamo: SoundLayer = DYNAMO.new()
	dynamo.configure(spec)
	var tone := render(dynamo, int(RATE), ctx(3000.0, 0.0))
	var p600 := goertzel(tone, 600.0) # 3000/60 * 1 * 12
	var p400 := goertzel(tone, 400.0)
	check(p600 >= 5.0 * p400, "600 Hz alternator tone (%f) should dominate 400 Hz (%f)" % [p600, p400])
	check(render(DYNAMO.new(), 4410, ctx(3000.0, 0.0, false)).is_empty() == false, "dynamo render failed")
	var stopped: SoundLayer = DYNAMO.new()
	stopped.configure(spec)
	var s := render(stopped, 4410, ctx(3000.0, 0.0, false))
	var silent := true
	for v in s:
		if v != 0.0:
			silent = false
	check(silent, "dynamo is silent when the engine is stopped")

	var starter_spec := EngineSpec.new()
	starter_spec.starter_reduction = 4.4
	starter_spec.starter_segments = 17
	var starter: SoundLayer = STARTER.new()
	starter.configure(starter_spec)
	var whirr := render(starter, int(0.2 * RATE), ctx(1000.0, 1.0))
	check(whirr.size() > 0, "starter produced no samples")
	var finite := true
	for v in whirr:
		if not is_finite(v):
			finite = false
	check(finite, "starter samples are finite")
	var released: SoundLayer = STARTER.new()
	released.configure(starter_spec)
	var quiet := render(released, int(0.2 * RATE), ctx(1000.0, 0.0))
	var all_zero := true
	for v in quiet:
		if v != 0.0:
			all_zero = false
	check(all_zero, "starter is silent when released")

	print("starter_dynamo_layer_test: %s" % ("PASSED" if _fails == 0 else "FAILED"))
	quit(0 if _fails == 0 else 1)