class_name TurboLayer
extends SoundLayer

# Turbo whistle, wastegate flutter and blow-off. Silent unless the bike has a turbo or supercharger; the electric
# compressor whine is a separate layer and is not added here.

const WHISTLE_HZ := 1500.0 # turbine tone at no boost
const WHISTLE_RISE_HZ := 6000.0 # how far the tone climbs at full spool
const VIBRATO_HZ := 5.0 # slow wobble of the tone
const VIBRATO_DEPTH := 0.01 # 1 percent of the tone's pitch
const WHISTLE_AMP := 0.10 # tone amplitude at full spool
const AIR_RATIO := 0.3 # breathy noise under the tone, relative to the tone
const SPOOL_TIME := 0.2 # seconds for the turbo to follow boost, since the turbine has inertia
const WASTEGATE_RATE := 12.0 # flutter chirps per second
const WASTEGATE_JITTER := 0.3 # chirp timing spread, as a fraction of the gap between chirps
const WASTEGATE_BOOST := 1.5 # the wastegate only flutters above this boost ratio
const WASTEGATE_AMP := 0.05 # chirp amplitude
const CHIRP_LEN := 0.015 # chirp length, seconds
const CHIRP_TAU := 0.004 # chirp decay, seconds
const LIFT_DROP := 0.3 # throttle fall that counts as a lift
const LIFT_WINDOW := 0.15 # seconds over which that fall must happen
const BLOW_BOOST := 1.2 # blow-off needs boost behind the throttle to sound
const BLOW_AMP := 0.15 # blow-off amplitude at full spool
const BLOW_TAU := 0.25 # blow-off decay, seconds
const BLOW_COOLDOWN := 0.5 # shortest gap between two blow-offs, seconds

var _rng := RandomNumberGenerator.new()
var _spool := 0.0
var _tone_phase := 0.0
var _vib_phase := 0.0
var _air_2k := 0.0 # one-pole lowpass states; a band is the difference of two of them
var _air_6k := 0.0
var _chirp_2k := 0.0
var _chirp_5k := 0.0
var _blow_3k := 0.0
var _blow_9k := 0.0
var _chirp_wait := 0 # samples until the next wastegate chirp
var _chirp_left := 0 # samples left in the current chirp
var _chirp_env := 0.0
var _blow_env := 0.0
var _peak := 0.0 # highest throttle within the last LIFT_WINDOW
var _peak_age := 0.0 # seconds since _peak was set
var _cooldown := 0.0 # seconds until another blow-off is allowed

var _spool_k := 1.0 - exp(-1.0 / (RATE * SPOOL_TIME)) # per-sample smoothing factor
var _chirp_len := int(CHIRP_LEN * RATE)
var _chirp_decay := exp(-1.0 / (CHIRP_TAU * RATE))
var _blow_decay := exp(-1.0 / (BLOW_TAU * RATE))
var _a_air_2k := _alpha(2000.0)
var _a_air_6k := _alpha(6000.0)
var _a_chirp_2k := _alpha(2000.0)
var _a_chirp_5k := _alpha(5000.0)
var _a_blow_3k := _alpha(3000.0)
var _a_blow_9k := _alpha(9000.0)


func _init() -> void:
	reset()


# Clears every state and reseeds the noise, so a restarted engine renders the same sound again.
func reset() -> void:
	_rng.seed = 7
	_spool = 0.0
	_tone_phase = 0.0
	_vib_phase = 0.0
	_air_2k = 0.0
	_air_6k = 0.0
	_chirp_2k = 0.0
	_chirp_5k = 0.0
	_blow_3k = 0.0
	_blow_9k = 0.0
	_chirp_wait = 0
	_chirp_left = 0
	_chirp_env = 0.0
	_blow_env = 0.0
	_peak = 0.0
	_peak_age = 0.0
	_cooldown = 0.0


func render(frames: int, c: SoundContext) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(frames)

	# Track the throttle peak even when silent, so a lift is seen the moment the engine runs.
	var dt := float(frames) / RATE
	_peak_age += dt
	if c.throttle >= _peak or _peak_age > LIFT_WINDOW:
		_peak = c.throttle
		_peak_age = 0.0
	_cooldown = maxf(_cooldown - dt, 0.0)

	if not c.turbo or not c.running or c.rpm < 1.0:
		return out

	var target := clampf((c.boost_ratio - 1.0) / 0.8, 0.0, 1.0) # 0 at no boost, 1 at 1.8
	# A lift is the throttle falling well below its recent peak with boost behind it: the diverter valve dumps the pressure.
	if _peak - c.throttle > LIFT_DROP and c.boost_ratio > BLOW_BOOST and _cooldown <= 0.0:
		_blow_env = BLOW_AMP * target
		_cooldown = BLOW_COOLDOWN
	var flutter := c.boost_ratio > WASTEGATE_BOOST

	for i in frames:
		_spool += (target - _spool) * _spool_k
		_vib_phase = fposmod(_vib_phase + TAU * VIBRATO_HZ / RATE, TAU)
		var freq := (WHISTLE_HZ + WHISTLE_RISE_HZ * _spool) * (1.0 + VIBRATO_DEPTH * sin(_vib_phase))
		_tone_phase = fposmod(_tone_phase + TAU * freq / RATE, TAU) # phase carries over, so block edges do not click
		var tone := sin(_tone_phase) * WHISTLE_AMP * _spool

		# Every noise source draws its own random numbers, every sample, so the draw count never depends on state.
		var n_air := _rng.randf_range(-1.0, 1.0)
		_air_2k += _a_air_2k * (n_air - _air_2k)
		_air_6k += _a_air_6k * (n_air - _air_6k)
		var air := (_air_6k - _air_2k) * AIR_RATIO * WHISTLE_AMP * _spool

		_chirp_wait -= 1
		if _chirp_wait <= 0:
			_chirp_wait = int(RATE / WASTEGATE_RATE * (1.0 + WASTEGATE_JITTER * _rng.randf_range(-1.0, 1.0)))
			if flutter:
				_chirp_env = 1.0
				_chirp_left = _chirp_len
		var n_chirp := _rng.randf_range(-1.0, 1.0)
		_chirp_2k += _a_chirp_2k * (n_chirp - _chirp_2k)
		_chirp_5k += _a_chirp_5k * (n_chirp - _chirp_5k)
		var chirp := 0.0
		if _chirp_left > 0: # a chirp lasts only its 15 ms, so the envelope never leaves a tail
			_chirp_left -= 1
			chirp = (_chirp_5k - _chirp_2k) * _chirp_env * WASTEGATE_AMP
			_chirp_env *= _chirp_decay

		var n_blow := _rng.randf_range(-1.0, 1.0)
		_blow_3k += _a_blow_3k * (n_blow - _blow_3k)
		_blow_9k += _a_blow_9k * (n_blow - _blow_9k)
		var blow := (_blow_9k - _blow_3k) * _blow_env
		_blow_env *= _blow_decay

		out[i] = tone + air + chirp + blow
	return out


# One-pole lowpass coefficient for a cutoff in Hz.
static func _alpha(cutoff: float) -> float:
	return 1.0 - exp(-TAU * cutoff / RATE)
