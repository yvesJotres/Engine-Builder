class_name ValvetrainLayer
extends SoundLayer

# Valve tick and cam chain rattle. Only four-stroke engines have poppet valves, so a two-stroke gets silence.

const SEED := 4417 # fixed seed, so the same engine state always renders the same sound
const TICK_DECAY_S := 0.003 # click decay: short enough to read as a tick, not a ring
const TICK_GAIN := 0.15
const CHAIN_GAIN := 0.08
const JITTER := 0.15 # click timing jitter, as a share of the event interval
const EV_INTAKE_OPEN := 0.55 # valve opening is softer than the seat impact
const EV_INTAKE_CLOSE := 0.95
const EV_EXHAUST_OPEN := 0.45
const EV_EXHAUST_CLOSE := 1.20
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
var _configured := false
var _cylinders := 0
var _intake_open := 0.0
var _intake_close := 0.0
var _exhaust_open := 0.0
var _exhaust_close := 0.0
var _phases := PackedFloat64Array() # per-cylinder crank phase, advanced inside a block


func _init() -> void:
	_rng.seed = SEED
	_tick_decay = exp(-1.0 / (TICK_DECAY_S * SoundLayer.RATE))
	# one-pole filters: high-pass at 1.5 kHz and low-pass at 4 kHz for the tick, 800 Hz and 3 kHz for the chain
	_tick_hp_a = _pole(1500.0)
	_tick_lp_b = 1.0 - _pole(4000.0)
	_chain_hp_a = _pole(800.0)
	_chain_lp_b = 1.0 - _pole(3000.0)


func configure(spec: EngineSpec) -> void:
	_cylinders = maxi(spec.cylinders, 1)
	_intake_open = spec.intake_open_deg()
	_intake_close = spec.intake_close_deg()
	_exhaust_open = spec.exhaust_open_deg()
	_exhaust_close = spec.exhaust_close_deg()
	_configured = true
	reset()


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
	_phases = PackedFloat64Array()


func render(frames: int, c: SoundContext) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(frames)
	if not c.four_stroke or not c.running or c.rpm < 1.0:
		# Move the grid up while silent, so a restart does not fire every click it missed at once.
		_clock += float(frames)
		_slot = _clock
		_next_click = _clock
		_click_env = 0.0
		_phases = PackedFloat64Array()
		return out

	# Each valve opens and closes once per two crank turns, so events per second = cylinders * valves * rpm / 60.
	var interval := SoundLayer.RATE * 60.0 / (float(maxi(c.cylinders, 1) * maxi(c.valves_per_cylinder, 1)) * c.rpm)
	interval = maxf(interval, 2.0)
	# The tick gets louder up to 4000 rpm and then holds, since the valve noise stops rising with speed.
	var tick_gain := lerpf(0.5, 1.0, clampf(c.rpm / 4000.0, 0.0, 1.0)) * TICK_GAIN
	# The chain rattle is the idle sound and fades out as the engine speeds up.
	var chain_gain := clampf(1.0 - c.rpm / 5000.0, 0.0, 1.0) * CHAIN_GAIN

	# With live cylinder phases, put the click on the real valve event. Otherwise keep the uniform grid
	# fallback, which is still useful for a bare SoundContext in tests.
	var use_phases := _configured and c.cylinder_phase_deg.size() > 0
	if use_phases:
		if _phases.size() != c.cylinder_phase_deg.size():
			_phases.resize(c.cylinder_phase_deg.size())
		for ci in c.cylinder_phase_deg.size():
			_phases[ci] = c.cylinder_phase_deg[ci]
	var step_deg := c.rpm * 6.0 / SoundLayer.RATE # crank degrees per sample

	for i in frames:
		if use_phases:
			for ci in _phases.size():
				var prev := _phases[ci]
				var cur := fposmod(prev + step_deg, 720.0)
				if _crossed_event(prev, cur, _intake_open, step_deg):
					_click_env += EV_INTAKE_OPEN * _rng.randf_range(0.8, 1.0) * tick_gain
				if _crossed_event(prev, cur, _intake_close, step_deg):
					_click_env += EV_INTAKE_CLOSE * _rng.randf_range(0.8, 1.0) * tick_gain
				if _crossed_event(prev, cur, _exhaust_open, step_deg):
					_click_env += EV_EXHAUST_OPEN * _rng.randf_range(0.8, 1.0) * tick_gain
				if _crossed_event(prev, cur, _exhaust_close, step_deg):
					_click_env += EV_EXHAUST_CLOSE * _rng.randf_range(0.8, 1.0) * tick_gain
				_phases[ci] = cur
		else:
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


static func _crossed_event(prev: float, cur: float, at: float, step_deg: float) -> bool:
	var rel := fposmod(at - prev, 720.0)
	return rel > 0.0 and rel <= step_deg
