class_name MechanicalLayer
extends SoundLayer

# Bottom-end sound: bearing rumble and the primary gear mesh whine. The rumble is low-passed noise that grows with rpm. The whine
# is a tone at the primary gear mesh frequency, crank rpm / 60 times the tooth count.

const RUMBLE_GAIN := 0.08 # rumble peak at the loudest; the low-passed noise never leaves -1..1, so this is the peak
const WHINE_GAIN := 0.04 # whine amplitude before the load factor
const CRANK_GEAR_TEETH := 23.0 # crank pinion teeth (estimate): sets the mesh tooth-passing rate
const WHINE_MAX_HZ := 18000.0 # above this the mesh tone is halved until it is under, to keep clear of Nyquist
const SMOOTH_S := 0.02 # glide time for whine frequency and amplitude, so rpm and load steps do not click
const FADE_IN_S := 1.5 # the gear whine rises over this time after the engine fires
const SEED := 7141

var _rng := RandomNumberGenerator.new()
var _lp := 0.0 # low-pass state of the rumble noise
var _phase := 0.0 # whine phase in cycles, carried between blocks
var _freq := 0.0 # smoothed whine frequency, Hz
var _amp := 0.0 # smoothed whine amplitude


func _init() -> void:
	reset()


# Clears every state, for an engine restart. The seed is fixed so a render is the same every time.
func reset() -> void:
	_rng.seed = SEED
	_lp = 0.0
	_phase = 0.0
	_freq = 0.0
	_amp = 0.0


# Smooth 0-to-1 ramp over FADE_IN_S after the engine starts firing.
static func _fade_in(fire_time: float) -> float:
	var x := clampf(fire_time / FADE_IN_S, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


func render(frames: int, c: SoundContext) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(frames)
	if not c.running or c.rpm < 1.0:
		return out # silent; the state is kept so the next block carries on cleanly

	# One-pole low-pass coefficient for the rumble; the cutoff rises slowly with rpm.
	var a := 1.0 - exp(-TAU * (120.0 + c.rpm * 0.05) / SoundLayer.RATE)
	var rumble := pow(clampf(c.rpm / 12000.0, 0.0, 1.0), 0.7) * RUMBLE_GAIN

	# The mesh tone is the crank gear's tooth-passing rate: crank rpm / 60 times the crank gear's teeth. The primary ratio is
	# already in the basket's speed, so it is not applied again. 23 teeth is an estimate for a crank pinion, not a measured value.
	var target_f := c.rpm / 60.0 * CRANK_GEAR_TEETH
	while target_f > WHINE_MAX_HZ:
		target_f *= 0.5
	# squared load: the mesh is faint at idle and only comes through under throttle, where the gears carry torque
	var target_amp := WHINE_GAIN * clampf(c.load, 0.0, 1.0) * clampf(c.load, 0.0, 1.0) * _fade_in(c.fire_time) * c.gear_whine

	# Per-sample glide toward the targets; a one-pole with the 20 ms time constant.
	var k := 1.0 - exp(-1.0 / (SoundLayer.RATE * SMOOTH_S))
	for i in frames:
		_lp += a * (_rng.randf_range(-1.0, 1.0) - _lp)
		_freq += (target_f - _freq) * k
		_amp += (target_amp - _amp) * k
		_phase = fmod(_phase + _freq / SoundLayer.RATE, 1.0)
		# A slightly detuned partial at 1.5 times the mesh frequency, so the whine has the grit of gears instead of a pure whistle.
		# shortcut: no second harmonic at 2x, which made a whistle near 3 kHz; upgrade to a real gear-tooth spectrum if this still reads thin.
		# a gear mesh is a pure tone at its tooth-passing rate, with the sidebands of its load; there is no 1.5x partial in a real mesh
		var tone := sin(TAU * _phase)
		out[i] = float(_lp * rumble + tone * _amp)
	return out
