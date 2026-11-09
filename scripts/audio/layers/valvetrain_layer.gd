class_name ValvetrainLayer
extends SoundLayer

# Valve tick and cam chain rattle. Only four-stroke engines have poppet valves, so a two-stroke gets silence.

const SEED := 4417 # fixed seed, so the same engine state always renders the same sound
const TICK_DECAY_S := 0.003 # click decay: short enough to read as a tick, not a ring
const TICK_GAIN := 0.15
const CHAIN_GAIN := 0.08
const JITTER := 0.15 # click timing jitter, as a share of the event interval
const LIMIT := 0.2 # soft ceiling, so overlapping clicks never pass the nominal peak
const CHAIN_MOD_SAMPLES := 2205.0 # the chain level picks a new target every 50 ms
const CHAIN_SMOOTH := 0.0005 # chain level glides to its target over about 45 ms

var _rng := RandomNumberGenerator.new()
var _clock := 0.0 # samples rendered so far
var _slot := 0.0 # grid position of the next valve event
var _next_click := 0.0 # when the next click sounds, jittered off the grid
var _click_env := 0.0 # decaying level of all clicks still ringing
var _tick_decay := 0.0
var _tick_hp_a := 0.0
var _tick_hp_x := 0.0
var _tick_hp_y := 0.0
var _tick_lp_b := 0.0
var _tick_lp := 0.0
var _chain_hp_a := 0.0
var _chain_hp_x := 0.0
var _chain_hp_y := 0.0
var _chain_lp_b := 0.0
var _chain_lp := 0.0
var _chain_am := 0.5 # slowly wandering chain level
var _chain_target := 0.5
var _chain_next := 0.0 # clock value at which the chain picks a new target


func _init() -> void:
	_rng.seed = SEED
	_tick_decay = exp(-1.0 / (TICK_DECAY_S * SoundLayer.RATE))
	# one-pole filters: high-pass at 1.5 kHz and low-pass at 4 kHz for the tick, 800 Hz and 3 kHz for the chain
	_tick_hp_a = _pole(1500.0)
	_tick_lp_b = 1.0 - _pole(4000.0)
	_chain_hp_a = _pole(800.0)
	_chain_lp_b = 1.0 - _pole(3000.0)


func _pole(hz: float) -> float:
	return exp(-2.0 * PI * hz / SoundLayer.RATE)


func reset() -> void:
	_rng.seed = SEED
	_clock = 0.0
	_slot = 0.0
	_next_click = 0.0
	_click_env = 0.0
	_tick_hp_x = 0.0
	_tick_hp_y = 0.0
	_tick_lp = 0.0
	_chain_hp_x = 0.0
	_chain_hp_y = 0.0
	_chain_lp = 0.0
	_chain_am = 0.5
	_chain_target = 0.5
	_chain_next = 0.0


func render(frames: int, c: SoundContext) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(frames)
	if not c.four_stroke or not c.running or c.rpm < 1.0:
		# Move the grid up while silent, so a restart does not fire every click it missed at once.
		_clock += float(frames)
		_slot = _clock
		_next_click = _clock
		_click_env = 0.0
		return out

	# Each valve opens and closes once per two crank turns, so events per second = cylinders * valves * rpm / 60.
	var interval := SoundLayer.RATE * 60.0 / (float(maxi(c.cylinders, 1) * maxi(c.valves_per_cylinder, 1)) * c.rpm)
	interval = maxf(interval, 2.0)
	# The tick gets louder up to 4000 rpm and then holds, since the valve noise stops rising with speed.
	var tick_gain := lerpf(0.5, 1.0, clampf(c.rpm / 4000.0, 0.0, 1.0)) * TICK_GAIN
	# The chain rattle is the idle sound and fades out as the engine speeds up.
	var chain_gain := clampf(1.0 - c.rpm / 5000.0, 0.0, 1.0) * CHAIN_GAIN

	for i in frames:
		while _clock >= _next_click:
			_click_env += _rng.randf_range(0.6, 1.0) * tick_gain
			_slot += interval
			_next_click = _slot + _rng.randf_range(-JITTER, JITTER) * interval

		var x := _rng.randf_range(-1.0, 1.0)
		var hp := _tick_hp_a * (_tick_hp_y + x - _tick_hp_x)
		_tick_hp_x = x
		_tick_hp_y = hp
		_tick_lp += _tick_lp_b * (hp - _tick_lp)
		var v := _tick_lp * _click_env
		_click_env *= _tick_decay

		if _clock >= _chain_next:
			_chain_target = _rng.randf_range(0.2, 1.0)
			_chain_next += CHAIN_MOD_SAMPLES
		_chain_am += (_chain_target - _chain_am) * CHAIN_SMOOTH
		var y := _rng.randf_range(-1.0, 1.0)
		var chp := _chain_hp_a * (_chain_hp_y + y - _chain_hp_x)
		_chain_hp_x = y
		_chain_hp_y = chp
		_chain_lp += _chain_lp_b * (chp - _chain_lp)
		v += _chain_lp * _chain_am * chain_gain

		out[i] = LIMIT * tanh(v / LIMIT)
		_clock += 1.0
	return out
