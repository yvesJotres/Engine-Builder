class_name DrivelineLayer
extends SoundLayer

# Gearbox and clutch sounds: gear whine, neutral and idle clutch rattle, gear change clunk and chain hum.

const WHINE_GAIN := 0.03 # gear whine at full load with the clutch engaged
const RATTLE_GAIN := 0.10 # clutch click level at standstill
const RATTLE_RPM := 2500.0 # above this the clutch rattle is gone
const CLICK_RATE := 0.5 # clicks per engine revolution
const CLICK_DECAY_S := 0.003 # a click burst dies away in about 3 ms
const CLICK_LIFT := 8.0 # the narrow band keeps little noise power, so this lifts a click to the level its gain says
const CLUNK_GAIN := 0.15
const CLUNK_HZ := 130.0
const CLUNK_DECAY_S := 0.08
const CLUNK_LEN_S := 0.4 # five decay times, then the clunk is over
const CLUNK_CLICK := 0.04 # the 2 ms noise tick at the start of a clunk
const CHAIN_GAIN := 0.03
const SMOOTH_S := 0.02 # one-pole time for pitch and level, so steps do not click
const SEED := 1234


# Band-pass biquad (RBJ cookbook, constant peak gain) for shaping white noise.
class BandPass:
	var b0 := 0.0
	var b2 := 0.0
	var a1 := 0.0
	var a2 := 0.0
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0

	func _init(hz: float, q: float) -> void:
		var w := TAU * hz / SoundLayer.RATE
		var alpha := sin(w) / (2.0 * q)
		var a0 := 1.0 + alpha
		b0 = alpha / a0
		b2 = -alpha / a0
		a1 = -2.0 * cos(w) / a0
		a2 = (1.0 - alpha) / a0

	func step(x: float) -> float:
		var y := b0 * x + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
		return y


var _rng := RandomNumberGenerator.new()
var _freq := 0.0 # smoothed whine frequency
var _phase := 0.0 # whine oscillator phase
var _whine_level := 0.0 # smoothed whine level
var _hum_level := 0.0 # smoothed chain hum level
var _click_timer := 0.0 # seconds until the next rattle click
var _click_env := 0.0 # envelope of the click now sounding
var _click_bp: BandPass
var _hum_bp: BandPass
var _clunk_t := -1.0 # seconds since the clunk started, -1 when none
var _last_gear := 0
var _gear_known := false


func _init() -> void:
	reset()


func configure(_spec: EngineSpec) -> void:
	reset()


func reset() -> void:
	_rng.seed = SEED
	_freq = 0.0
	_phase = 0.0
	_whine_level = 0.0
	_hum_level = 0.0
	_click_timer = 0.0
	_click_env = 0.0
	_click_bp = BandPass.new(2000.0, 1.0)
	_hum_bp = BandPass.new(950.0, 1.0)
	_clunk_t = -1.0
	_last_gear = 0
	_gear_known = false


func render(frames: int, c: SoundContext) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(frames)
	# the first block only remembers the gear, so starting up never clunks
	if not _gear_known:
		_last_gear = c.gear
		_gear_known = true
	var shifted := c.gear != _last_gear
	_last_gear = c.gear
	if not c.running or c.rpm < 1.0:
		return out
	if shifted:
		_clunk_t = 0.0

	# the input shaft turns at engine speed over the primary ratio, and 17 teeth mesh with the gear
	var f := c.rpm / maxf(c.primary_ratio, 0.5) / 60.0 * 17.0
	while f >= 18000.0: # halve it, the tone is inaudible up there and only wastes the mix
		f *= 0.5
	var whine_target := WHINE_GAIN * c.clutch_engage * (0.35 + 0.65 * c.load) if c.gear > 0 else 0.0
	# a dry clutch rattles only when it is not carrying drive: in neutral, or open at idle
	var rattle := (c.gear == 0 or c.clutch_engage < 0.3) and c.rpm < RATTLE_RPM
	var click_level := RATTLE_GAIN * clampf(1.0 - c.rpm / RATTLE_RPM, 0.0, 1.0)
	var click_rate := c.rpm / 60.0 * CLICK_RATE
	# chain hum grows with road speed, and only shows when the clutch carries the drive
	var hum_target := CHAIN_GAIN * clampf(c.speed_ms / 12.0, 0.0, 1.0) if (c.gear > 0 and c.clutch_engage > 0.5) else 0.0

	var k := 1.0 - exp(-1.0 / (SMOOTH_S * SoundLayer.RATE))
	var click_decay := exp(-1.0 / (CLICK_DECAY_S * SoundLayer.RATE))
	var dt := 1.0 / SoundLayer.RATE
	for i in frames:
		_freq += (f - _freq) * k
		_whine_level += (whine_target - _whine_level) * k
		_phase = fmod(_phase + TAU * _freq * dt, TAU)
		var s := _whine_level * sin(_phase)

		_hum_level += (hum_target - _hum_level) * k
		s += _hum_level * _hum_bp.step(_rng.randf_range(-1.0, 1.0))

		if rattle:
			_click_timer -= dt
			if _click_timer <= 0.0:
				_click_env = click_level
				# heavy jitter: a dry clutch clicks irregularly, not on a clock
				_click_timer = 1.0 / click_rate * _rng.randf_range(0.2, 1.8)
		s += _click_bp.step(_rng.randf_range(-1.0, 1.0)) * CLICK_LIFT * _click_env
		_click_env *= click_decay

		if _clunk_t >= 0.0:
			s += CLUNK_GAIN * exp(-_clunk_t / CLUNK_DECAY_S) * sin(TAU * CLUNK_HZ * _clunk_t)
			if _clunk_t < 0.002:
				s += CLUNK_CLICK * _rng.randf_range(-1.0, 1.0)
			_clunk_t += dt
			if _clunk_t > CLUNK_LEN_S:
				_clunk_t = -1.0

		# layers add up past the nominal 0.2 when a clunk lands on a rattle, so clamp the sum
		out[i] = clampf(s, -0.2, 0.2)
	return out
