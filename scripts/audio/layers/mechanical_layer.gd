class_name MechanicalLayer
extends SoundLayer

# Bottom-end sound: bearing rumble and the primary gear mesh whine. The rumble is low-passed noise that grows with rpm. The whine
# is a tone at the primary gear mesh frequency, crank rpm / 60 times the tooth count.

const RUMBLE_GAIN := 0.08 # rumble peak at the loudest; the low-passed noise never leaves -1..1, so this is the peak
const WHINE_GAIN := 0.04 # whine amplitude before the load factor
const WHINE_MAX_HZ := 18000.0 # above this the mesh tone is halved until it is under, to keep clear of Nyquist
const SMOOTH_S := 0.02 # glide time for whine frequency and amplitude, so rpm and load steps do not click
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


func render(frames: int, c: SoundContext) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(frames)
	if not c.running or c.rpm < 1.0:
		return out # silent; the state is kept so the next block carries on cleanly

	# One-pole low-pass coefficient for the rumble; the cutoff rises slowly with rpm.
	var a := 1.0 - exp(-TAU * (120.0 + c.rpm * 0.05) / SoundLayer.RATE)
	var rumble := pow(clampf(c.rpm / 12000.0, 0.0, 1.0), 0.7) * RUMBLE_GAIN

	# Teeth from the primary ratio, never fewer than 12 so a tiny ratio still gives a sensible mesh tone.
	var teeth := maxi(12, roundi(23.0 * c.primary_ratio))
	var target_f := c.rpm / 60.0 * teeth
	while target_f > WHINE_MAX_HZ:
		target_f *= 0.5
	var target_amp := WHINE_GAIN * (0.3 + 0.7 * clampf(c.load, 0.0, 1.0))

	# Per-sample glide toward the targets; a one-pole with the 20 ms time constant.
	var k := 1.0 - exp(-1.0 / (SoundLayer.RATE * SMOOTH_S))
	for i in frames:
		_lp += a * (_rng.randf_range(-1.0, 1.0) - _lp)
		_freq += (target_f - _freq) * k
		_amp += (target_amp - _amp) * k
		_phase = fmod(_phase + _freq / SoundLayer.RATE, 1.0)
		# The half-amplitude second harmonic is dropped once it would pass Nyquist, where it would alias.
		var harmonic := 0.5 if _freq * 2.0 < SoundLayer.RATE * 0.5 else 0.0
		var tone := sin(TAU * _phase) + harmonic * sin(TAU * 2.0 * _phase)
		out[i] = float(_lp * rumble + tone * _amp)
	return out
