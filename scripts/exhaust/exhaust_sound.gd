class_name ExhaustSound
extends RefCounted

# The exhaust side of the playback chain: the tail volume flow from ExhaustGas becomes a pulse with its edge and a little
# colored noise for rasp. Remove the standing flow (high-pass), smooth it, take the edge, mix in rasp noise. EngineSound
# then convolves the result with the muffler impulse response.

const RATE := 44100.0
const BASE_FLOW_SCALE := 28.0 # calibrated for ~150 cc; the leveler sets the loudness, see EngineSound.setup
const EDGE_MIX := 0.55 # share of the sample-to-sample change; the rest is the flow
const NOISE_MIX := 0.22 # rasp on the pulse. Most of the sample is the pulse itself
const SMOOTH_HZ := 1900.0
const DC_HZ := 10.0
const NOISE_HZ := 2000.0
const LEVEL_TARGET := 0.4
const LEVEL_DECAY := 0.9996
const LEVEL_FOLLOW := 0.04
const LEVEL_MIN := 0.04
const LEVEL_MAX := 5.0

var starved := false # set when the flow runs out mid-sound; EngineSound copies it out and clears it
var noise_mix := NOISE_MIX
var nz := 0.0 # low-passed white noise for the rasp

var _flow := PackedFloat32Array()
var _read := 0
var _q := 0.0
var _lp := 0.0
var _dc := 0.0
var _prev_f := 0.0
var _rng := 1
var _lp_a := 0.2
var _dc_a := 0.001
var _nz_a := 0.2
var _edge_mix := EDGE_MIX
var _flow_scale := BASE_FLOW_SCALE
var _last_sample := 0.0
var _peak := 0.2
var _gain := 1.0
var _lambda := 1.0
var _egt_c := 400.0
var _back_pa := 101325.0


func _init() -> void:
	reset()


func reset() -> void:
	_flow = PackedFloat32Array()
	_read = 0
	_q = 0.0
	_lp = 0.0
	_dc = 0.0
	_prev_f = 0.0
	_rng = 1
	nz = 0.0
	_edge_mix = EDGE_MIX
	noise_mix = NOISE_MIX
	_lambda = 1.0
	_egt_c = 400.0
	_back_pa = 101325.0
	_last_sample = 0.0
	_peak = 0.2
	_gain = 1.0
	_flow_scale = BASE_FLOW_SCALE
	starved = false
	_lp_a = alpha(SMOOTH_HZ)
	_dc_a = alpha(DC_HZ)
	_nz_a = alpha(NOISE_HZ)


# Appends tail flow samples to the queue the sound reads from.
func push(samples: PackedFloat32Array) -> void:
	if _read > 4096:
		_flow = _flow.slice(_read)
		_read = 0
	var base := _flow.size()
	_flow.resize(base + samples.size())
	for i in samples.size():
		_flow[base + i] = samples[i]


# Lambda, exhaust temperature and the pressure at the exhaust valve. They nudge rasp, brightness and edge.
# A lambda of 99 means the cylinder has not burned yet, so it is ignored. rasp_scale is the panel's rasp level.
func set_conditions(lambda: float, egt_c: float, backpressure_pa: float, rasp_scale: float) -> void:
	if lambda < 50.0:
		_lambda = lerpf(_lambda, lambda, 0.2)
	_egt_c = lerpf(_egt_c, egt_c, 0.1)
	_back_pa = lerpf(_back_pa, backpressure_pa, 0.2)
	var hot := clampf((_egt_c - 250.0) / 550.0, 0.0, 1.0)
	var stuffed := clampf((_back_pa - 101325.0) / 30000.0, 0.0, 1.0)
	var lean := clampf((_lambda - 0.9) / 0.25, 0.0, 1.0)
	_lp_a = alpha(lerpf(1500.0, 2600.0, hot) * lerpf(1.0, 0.7, stuffed))
	_edge_mix = lerpf(EDGE_MIX, EDGE_MIX * 0.6, stuffed)
	noise_mix = lerpf(0.14, 0.34, lean) * rasp_scale


# One exhaust sample per audio sample: the shaped pulse with its edge and rasp.
func excite() -> float:
	var fresh := false
	if _read < _flow.size():
		fresh = true
		_q = _flow[_read]
		_read += 1
		nz += _nz_a * (_white() - nz)
	elif not _flow.is_empty():
		starved = true
		_q += (0.0 - _q) * 0.02
	else:
		_q = _last_sample * 0.999
	_lp += _lp_a * (_q - _lp)
	_dc += _dc_a * (_lp - _dc)
	var flow := (_lp - _dc) * _flow_scale
	var edge := flow - _prev_f
	_prev_f = flow
	# A repeated sample is not new turbulence. New noise there becomes a hiss with no exhaust pulse under it.
	var air := air_factor(fresh)
	_last_sample = edge * _edge_mix + flow * air * (1.0 - _edge_mix)
	return _last_sample


# Rasp factor for a sample: the noise on a fresh sample, unity on a repeated one. The intake uses the same factor.
func air_factor(fresh: bool) -> float:
	return noise_mix * nz + (1.0 - noise_mix) if fresh else 1.0


# Soft clip with a leveler: keeps the pulse near LEVEL_TARGET without a hard edge.
func shape(sample: float) -> float:
	_peak *= LEVEL_DECAY
	var mag := absf(sample)
	if mag > _peak:
		_peak = mag
	if _peak < 1e-8 or sample == 0.0:
		return 0.0
	var wanted := clampf(LEVEL_TARGET / _peak, LEVEL_MIN, LEVEL_MAX)
	_gain = lerpf(_gain, wanted, LEVEL_FOLLOW)
	return tanh(sample * _gain)


func _white() -> float:
	_rng = (_rng * 1103515245 + 12345) & 0x7fffffff
	return float(_rng) / 1073741823.5 - 1.0


static func alpha(cutoff: float) -> float:
	var rc := 1.0 / (TAU * cutoff)
	var dt := 1.0 / RATE
	return dt / (rc + dt)
