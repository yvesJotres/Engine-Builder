extends SceneTree

# The supercharger layer: silent unless the blower flag and a running engine are set, its tone follows engine speed, and it
# is louder under load. Exits 1 on any failure.
# Run: godot --headless --path . -s res://tests/unit/audio/supercharger_layer_test.gd

const LAYER := preload("res://scripts/audio/layers/supercharger_layer.gd")
const BLOCK := 441

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func ctx(rpm: float, load: float, blower: bool, running: bool) -> SoundContext:
	var c := SoundContext.new()
	c.rpm = rpm
	c.load = load
	c.blower = blower
	c.running = running
	return c


func supercharger_spec(type: String = "roots") -> EngineSpec:
	var s := EngineSpec.new()
	s.supercharger_type = type
	s.supercharger_drive_ratio = 2.0
	s.supercharger_lobes = 3
	s.supercharger_blades = 9
	s.supercharger_shift_rpm = 0.0
	return s


func render(layer: SoundLayer, seconds: float, c: SoundContext) -> PackedFloat32Array:
	var total := int(seconds * SoundLayer.RATE)
	var out := PackedFloat32Array()
	var done := 0
	while done < total:
		var n := mini(BLOCK, total - done)
		out.append_array(layer.render(n, c))
		done += n
	return out


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


func _init() -> void:
	# 1. silent without the blower or with the engine stopped
	var off: SoundLayer = LAYER.new()
	off.configure(supercharger_spec())
	check(rms(render(off, 0.2, ctx(9000.0, 1.0, false, true))) == 0.0, "zeros without a blower")
	var stopped: SoundLayer = LAYER.new()
	stopped.configure(supercharger_spec())
	check(rms(render(stopped, 0.2, ctx(9000.0, 1.0, true, false))) == 0.0, "zeros when the engine is stopped")

	# 2. roots: 2:1 drive x 3 lobes -> 6 cycles per crank turn, so 9000 rpm gives 900 Hz
	var locked: SoundLayer = LAYER.new()
	locked.configure(supercharger_spec("roots"))
	var w := render(locked, 1.0, ctx(9000.0, 1.0, true, true))
	var tail := w.slice(22050)
	var at := goertzel(tail, 900.0)
	var off_tone := goertzel(tail, 500.0)
	check(at >= 10.0 * off_tone, "900 Hz power %s should dominate 500 Hz power %s" % [str(at), str(off_tone)])
	# centrifugal: 2:1 drive x 9 blades -> 18 cycles per crank turn, so 9000 rpm gives 2700 Hz
	var centrifugal: SoundLayer = LAYER.new()
	centrifugal.configure(supercharger_spec("centrifugal"))
	var cw := render(centrifugal, 1.0, ctx(9000.0, 1.0, true, true))
	var ctail := cw.slice(22050)
	var cat := goertzel(ctail, 2700.0)
	var coff := goertzel(ctail, 1800.0)
	check(cat >= 5.0 * coff, "2700 Hz power %s should dominate 1800 Hz power %s" % [str(cat), str(coff)])

	# 3. louder under load, and finite
	var light: SoundLayer = LAYER.new()
	light.configure(supercharger_spec())
	var heavy: SoundLayer = LAYER.new()
	heavy.configure(supercharger_spec())
	var quiet := rms(render(light, 0.5, ctx(9000.0, 0.0, true, true)))
	var loud := rms(render(heavy, 0.5, ctx(9000.0, 1.0, true, true)))
	check(loud > quiet * 2.0, "full load %f should be well above zero load %f" % [loud, quiet])
	check(is_finite(loud) and loud < 0.1, "output stays finite and small, got %f" % loud)

	print("supercharger_layer_test: %s" % ("PASSED" if _fails == 0 else "FAILED"))
	quit(0 if _fails == 0 else 1)
