class_name DynamoLayer
extends SoundLayer

# Alternator (dynamo) whine while the engine runs. The rotor turns at crank speed times a drive ratio, and the stator slots
# and rotor poles set the tone, so the pitch rises with rpm. Output, and so the whine, grows with rpm: it is faint at idle.
# The ratio and slot count are estimates until a service manual or spec sheet confirms them.

const DRIVE_RATIO := 1.0 # alternator turns per crank turn; 1.0 is a crank-mounted rotor
const SLOTS := 12.0 # rotor poles/slots, sets the whine order (estimate)
const WHINE_GAIN := 0.002 # whine level at full output: faint, a real alternator is barely audible over the engine
const FULL_OUTPUT_RPM := 6000.0 # the alternator is at full output here, quiet below
const LOW_OUTPUT := 0.1 # share of the level at zero rpm
const SMOOTH_S := 0.03
const HARMONIC_GAIN := 0.05 # the 2x partial is what gave the ghostly "ooo": kept low
const FADE_IN_S := 1.5 # the whine rises over this time after the engine fires

var _phase := 0.0
var _freq := 0.0
var _level := 0.0
var _ratio := DRIVE_RATIO
var _poles := SLOTS


func _init() -> void:
	reset()


# Smooth 0-to-1 ramp over FADE_IN_S after the engine starts firing.
static func _fade_in(fire_time: float) -> float:
	var x := clampf(fire_time / FADE_IN_S, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


func configure(spec: EngineSpec) -> void:
	_ratio = maxf(spec.alternator_drive_ratio, 0.0)
	_poles = maxf(spec.alternator_poles, 1.0)
	reset()


func reset() -> void:
	_phase = 0.0
	_freq = 0.0
	_level = 0.0


func render(frames: int, c: SoundContext) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(frames)
	var target := 0.0
	if c.running and c.rpm >= 1.0:
		var output := clampf(c.rpm / FULL_OUTPUT_RPM, LOW_OUTPUT, 1.0)
		target = WHINE_GAIN * output * _fade_in(c.fire_time)
	var f := c.rpm / 60.0 * _ratio * _poles
	var k := 1.0 - exp(-1.0 / (SMOOTH_S * SoundLayer.RATE))
	var dt := 1.0 / SoundLayer.RATE
	for i in frames:
		_freq += (f - _freq) * k
		_level += (target - _level) * k
		_phase = fmod(_phase + TAU * _freq * dt, TAU)
		out[i] = _level * (sin(_phase) + HARMONIC_GAIN * sin(2.0 * _phase))
	return out
