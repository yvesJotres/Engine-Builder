class_name StarterLayer
extends SoundLayer

# Starter motor while it is held. Three parts, from the physics of a brushed DC starter:
#  - brush whine: each commutator segment change makes the brush bounce on the step and ring the brush holder, so the
#    whine is a train of short ringing bursts at armature speed times the segment count, not a pure tone.
#  - pinion rattle: the pinion meshes with the crank once per turn, a short clatter that follows crank speed.
#  - relay click: the solenoid closes once when the starter engages.
# Gearing: a car-style gear-reduction starter is about 4.4:1 (vendor figure, not measured for a motorcycle). The segment
# count is a placeholder until the bike's starter spec is known.

const REDUCTION := 4.4 # armature turns per crank turn
const SEGMENTS := 17.0 # commutator segments (placeholder, see above)
const RING_DECAY_S := 0.0004 # the ring dies in about 0.4 ms
const WHINE_GAIN := 0.006 # brush whine level: a quiet texture under the exhaust, not a second engine
const RATTLE_GAIN := 0.015 # pinion rattle, one burst per crank turn
const NOISE_LP_HZ := 2500.0 # cutoff for the brush and rattle noise: the hiss stays in the mid band
const RATTLE_DECAY_S := 0.002
const COMPRESSION_DEPTH := 0.6 # how far the whine drops at each compression peak: the motor slows against the compressed charge
const CLICK_GAIN := 0.2 # relay click when the starter engages
const CLICK_LEN_S := 0.008
const SMOOTH_S := 0.02
const SEED := 4242

var _rng := RandomNumberGenerator.new()
var _seg_phase := 0.0 # armature segments passed, as a fraction of one segment
var _ring_env := 0.0
var _ring_phase := 0.0
var _rattle_env := 0.0
var _rattle_phase := 0.0 # crank turns since the last rattle burst, 0..1
var _click_t := -1.0 # seconds since the relay click began, -1 when none
var _was_held := false
var _level := 0.0
var _noise_lp := 0.0 # low-pass state of the brush and rattle noise
var _cycle_phase := 0.0 # compression cycles, 0..1


func _init() -> void:
	reset()


func configure(_spec: EngineSpec) -> void:
	reset()


func reset() -> void:
	_rng.seed = SEED
	_seg_phase = 0.0
	_ring_env = 0.0
	_ring_phase = 0.0
	_rattle_env = 0.0
	_rattle_phase = 0.0
	_click_t = -1.0
	_was_held = false
	_level = 0.0
	_cycle_phase = 0.0
	_noise_lp = 0.0


func render(frames: int, c: SoundContext) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(frames)
	var held := c.starter > 0.5
	if held and not _was_held:
		_click_t = 0.0 # the relay closes: one click
	_was_held = held
	if not held and _click_t < 0.0 and _ring_env < 1e-6 and _rattle_env < 1e-6:
		return out

	var dt := 1.0 / SoundLayer.RATE
	var seg_rate := c.rpm / 60.0 * REDUCTION * SEGMENTS # segment changes per second
	var rattle_rate := c.rpm / 60.0 # one burst per crank turn
	var ring_decay := exp(-dt / RING_DECAY_S)
	var rattle_decay := exp(-dt / RATTLE_DECAY_S)
	var gain := WHINE_GAIN * c.starter if held else 0.0
	var noise_a := 1.0 - exp(-TAU * NOISE_LP_HZ / SoundLayer.RATE)
	# one compression per cylinder every two crank turns (four-stroke), or one per turn (two-stroke)
	var cycle_rate := c.rpm / 60.0 * float(maxi(c.cylinders, 1)) / (2.0 if c.four_stroke else 1.0)
	for i in frames:
		var s := 0.0
		if held and c.rpm >= 1.0:
			_cycle_phase = fposmod(_cycle_phase + cycle_rate * dt, 1.0)
			var compression := 0.5 - 0.5 * cos(TAU * _cycle_phase) # 1 at the compression peak
			var whine_now := gain * (1.0 - COMPRESSION_DEPTH * compression)
			_seg_phase += seg_rate * dt
			if _seg_phase >= 1.0:
				_seg_phase -= 1.0
				_ring_env = whine_now # each segment change rings the brush holder
			_rattle_phase += rattle_rate * dt
			if _rattle_phase >= 1.0:
				_rattle_phase -= 1.0
				_rattle_env = RATTLE_GAIN * c.starter
		# broadband brush noise, not a tone: a fixed-pitch ring made a sustained "ooo" once the bursts overlapped
		# brush and rattle noise is low-passed: raw white noise made a hiss across the whole band
		_noise_lp += noise_a * (_rng.randf_range(-1.0, 1.0) - _noise_lp)
		s += _ring_env * _noise_lp
		_ring_env *= ring_decay

		s += _rattle_env * _noise_lp
		_rattle_env *= rattle_decay

		if _click_t >= 0.0:
			var env := 1.0 - _click_t / CLICK_LEN_S
			if env > 0.0:
				s += CLICK_GAIN * env * env * _rng.randf_range(-1.0, 1.0)
			_click_t += dt
			if _click_t > CLICK_LEN_S:
				_click_t = -1.0
		out[i] = clampf(s, -0.2, 0.2)
	return out
