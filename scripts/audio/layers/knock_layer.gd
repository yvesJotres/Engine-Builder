class_name KnockLayer
extends SoundLayer

# Detonation ping: each knock event rings the cylinder at about 6 and 9.5 kHz, a short metallic tick that dies in about 25 ms.

const PING_MAX := 8 # cap on pings sounding at once, so the cost stays fixed
const PINGS_PER_BLOCK := 4 # a big jump in knock_count is capped so one block cannot flood the mix
const STAGGER := 132 # 3 ms at 44.1 kHz, so a burst reads as separate pings
const FREQ_1 := 6000.0
const FREQ_2 := 9500.0
const JITTER := 0.08 # each ping is detuned up to 8 percent so repeated pings do not sound identical
const AMP_1 := 0.18
const AMP_2 := 0.12
const DECAY_1 := 0.025 # seconds, time constant of the decay
const DECAY_2 := 0.015 # the higher partial dies faster, as real ringing does
const PEAK := 0.2 # hard ceiling on the summed output
const ENV_FLOOR := 0.0001 # below this a ping is finished

var _rng := RandomNumberGenerator.new()
var _seen := false # the starting count has been taken
var _last_count := 0
var _wait := PackedInt32Array() # samples to skip before a ping starts
var _env1 := PackedFloat64Array() # envelope of partial 1, 0 when the slot is free
var _env2 := PackedFloat64Array()
var _ph1 := PackedFloat64Array() # oscillator phases, carried across blocks
var _ph2 := PackedFloat64Array()
var _w1 := PackedFloat64Array() # phase step per sample
var _w2 := PackedFloat64Array()


func configure(_spec: EngineSpec) -> void:
	reset()


# Clears every state, for an engine restart. The seed is fixed so a render is the same every time.
func reset() -> void:
	_rng.seed = 7
	_seen = false
	_last_count = 0
	for arr in [_wait, _env1, _env2, _ph1, _ph2, _w1, _w2]:
		arr.resize(PING_MAX)
		arr.fill(0)


func render(frames: int, c: SoundContext) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(frames)
	if _wait.is_empty():
		reset()

	# count the new knocks first, so a knock during silence is not played later
	var fresh := 0
	if _seen and c.knock_count > _last_count:
		fresh = mini(c.knock_count - _last_count, PINGS_PER_BLOCK)
	_seen = true
	_last_count = c.knock_count

	if not c.running or c.rpm < 1.0:
		_silence()
		return out

	for k in fresh:
		_trigger(k * STAGGER)

	var d1 := exp(-1.0 / (DECAY_1 * RATE))
	var d2 := exp(-1.0 / (DECAY_2 * RATE))
	for s in PING_MAX:
		if _env1[s] <= 0.0:
			continue
		var wait: int = _wait[s]
		var e1: float = _env1[s]
		var e2: float = _env2[s]
		var p1: float = _ph1[s]
		var p2: float = _ph2[s]
		var w1: float = _w1[s]
		var w2: float = _w2[s]
		for i in frames:
			if wait > 0:
				wait -= 1
				continue
			out[i] += float(AMP_1 * e1 * sin(p1) + AMP_2 * e2 * sin(p2))
			p1 = fmod(p1 + w1, TAU)
			p2 = fmod(p2 + w2, TAU)
			e1 *= d1
			e2 *= d2
			if e1 < ENV_FLOOR:
				e1 = 0.0
				e2 = 0.0
				break
		_wait[s] = wait
		_env1[s] = e1
		_env2[s] = e2
		_ph1[s] = p1
		_ph2[s] = p2

	# the summed pings must never exceed the contract peak, even when several overlap
	for i in frames:
		out[i] = clampf(out[i], -PEAK, PEAK)
	return out


# Starts a ping after delay samples, in a free slot, or in the quietest one if all are busy.
func _trigger(delay: int) -> void:
	var slot := 0
	var quietest := INF
	for s in PING_MAX:
		var level: float = _env1[s] + _env2[s]
		if level <= 0.0:
			slot = s
			break
		if level < quietest:
			quietest = level
			slot = s
	_wait[slot] = delay
	_env1[slot] = 1.0
	_env2[slot] = 1.0
	_ph1[slot] = 0.0
	_ph2[slot] = 0.0
	_w1[slot] = TAU * FREQ_1 * (1.0 + _rng.randf_range(-JITTER, JITTER)) / RATE
	_w2[slot] = TAU * FREQ_2 * (1.0 + _rng.randf_range(-JITTER, JITTER)) / RATE


# Frees every ping, so none resumes when the engine starts again.
func _silence() -> void:
	_wait.fill(0)
	_env1.fill(0.0)
	_env2.fill(0.0)
