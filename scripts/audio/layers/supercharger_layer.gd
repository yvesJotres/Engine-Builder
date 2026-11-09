class_name SuperchargerLayer
extends SoundLayer

# Mechanical supercharger whine: a rotor tone locked to engine speed, louder under load. Silent unless the bike has
# mechanical_blower set.

const TEETH := 12.0 # whine cycles per crank revolution, set by the blower's drive ratio
const WHINE_GAIN := 0.04 # whine amplitude at full load
const LOAD_FLOOR := 0.3 # share of the whine that stays at zero load (the rotor still spins over)
const SMOOTH_S := 0.03 # one-pole time for pitch and level
const HARMONIC_GAIN := 0.3 # second harmonic, gives the whine its edge

var _freq := 0.0
var _phase := 0.0
var _level := 0.0


func _init() -> void:
	reset()


func configure(_spec: EngineSpec) -> void:
	reset()


func reset() -> void:
	_freq = 0.0
	_phase = 0.0
	_level = 0.0


func render(frames: int, c: SoundContext) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(frames)
	var target := 0.0
	if c.blower and c.running and c.rpm >= 1.0:
		target = WHINE_GAIN * (LOAD_FLOOR + (1.0 - LOAD_FLOOR) * c.load)
	var f := c.rpm / 60.0 * TEETH
	var k := 1.0 - exp(-1.0 / (SMOOTH_S * SoundLayer.RATE))
	var dt := 1.0 / SoundLayer.RATE
	for i in frames:
		_freq += (f - _freq) * k
		_level += (target - _level) * k
		_phase = fmod(_phase + TAU * _freq * dt, TAU)
		out[i] = _level * (sin(_phase) + HARMONIC_GAIN * sin(2.0 * _phase))
	return out
