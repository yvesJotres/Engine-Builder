class_name SuperchargerLayer
extends SoundLayer

# Mechanical supercharger whine: a rotor tone locked to engine speed, louder under load. Silent unless the bike has
# mechanical_blower set.

const DRIVE_RATIO := 1.0 # default impeller/rotor turns per crank turn
const WHINE_GAIN := 0.04 # whine amplitude at full load
const LOAD_FLOOR := 0.3 # share of the whine that stays at zero load (the rotor still spins over)
const SMOOTH_S := 0.03 # one-pole time for pitch and level
const HARMONIC_GAIN := 0.3 # second harmonic, gives the whine its edge
const GEAR_GAIN := 0.25 # drive-gear mesh tone relative to the main whine

var _freq := 0.0
var _phase := 0.0
var _level := 0.0
var _gear_freq := 0.0
var _gear_phase := 0.0
var _drive_ratio := DRIVE_RATIO
var _high_ratio := 0.0
var _shift_rpm := 0.0
var _lobes := 3.0
var _blades := 9.0
var _gear_teeth := 0.0
var _type := "roots"


func _init() -> void:
	reset()


func configure(spec: EngineSpec) -> void:
	_type = spec.supercharger_type
	_drive_ratio = maxf(spec.supercharger_drive_ratio, 0.0)
	_high_ratio = maxf(spec.supercharger_high_drive_ratio, 0.0)
	_shift_rpm = maxf(spec.supercharger_shift_rpm, 0.0)
	_lobes = maxf(spec.supercharger_lobes, 1.0)
	_blades = maxf(spec.supercharger_blades, 1.0)
	_gear_teeth = maxf(spec.supercharger_gear_teeth, 0.0)
	reset()


func reset() -> void:
	_freq = 0.0
	_phase = 0.0
	_level = 0.0
	_gear_freq = 0.0
	_gear_phase = 0.0


func render(frames: int, c: SoundContext) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(frames)
	var target := 0.0
	if c.blower and c.running and c.rpm >= 1.0 and _type != "none":
		target = WHINE_GAIN * (LOAD_FLOOR + (1.0 - LOAD_FLOOR) * c.load)
	# A two-speed blower changes ratio at its shift rpm; otherwise one fixed drive ratio.
	var ratio := _drive_ratio
	if _high_ratio > 0.0 and _shift_rpm > 0.0 and c.rpm >= _shift_rpm:
		ratio = _high_ratio
	var orders := _lobes if _type == "roots" else _blades
	var f := minf(c.rpm / 60.0 * ratio * orders, RATE * 0.45)
	var f_gear := minf(c.rpm / 60.0 * ratio * _gear_teeth, RATE * 0.45) if _gear_teeth > 0.0 else 0.0
	var k := 1.0 - exp(-1.0 / (SMOOTH_S * SoundLayer.RATE))
	var dt := 1.0 / SoundLayer.RATE
	for i in frames:
		_freq += (f - _freq) * k
		_gear_freq += (f_gear - _gear_freq) * k
		_level += (target - _level) * k
		_phase = fmod(_phase + TAU * _freq * dt, TAU)
		_gear_phase = fmod(_gear_phase + TAU * _gear_freq * dt, TAU)
		var gear := GEAR_GAIN * sin(_gear_phase) if _gear_teeth > 0.0 else 0.0
		out[i] = _level * (sin(_phase) + HARMONIC_GAIN * sin(2.0 * _phase) + gear)
	return out
