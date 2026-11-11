class_name MechanicalLayer
extends SoundLayer

# Bottom-end sound: bearing rumble and a bearing resonance, the primary gear mesh whine with a tooth impact per mesh tooth, and a
# 2nd order torsional harmonic. The rumble is low-passed noise that grows with rpm. The whine is a tone at the gear mesh
# frequency, crank rpm / 60 times the tooth count.

const RUMBLE_GAIN := 0.08 # rumble peak at the loudest; the low-passed noise never leaves -1..1, so this is the peak
const RUMBLE_RESONANCE_GAIN := 0.15 # bearing growl resonance peak
const RUMBLE_RESONANCE_HZ := 400.0 # fixed bearing/structure mode, not a frequency that sweeps with rpm
const RESONANCE_BW_HZ := 80.0 # width of the bearing resonance band
const WHINE_GAIN := 0.04 # whine amplitude before the load factor
const CRANK_GEAR_TEETH := 23.0 # default crank pinion teeth; configure() reads the per-engine value
const WHINE_MAX_HZ := 18000.0 # above this the mesh tone is halved until it is under, to keep clear of Nyquist
const SMOOTH_S := 0.02 # glide time for whine frequency and amplitude, so rpm and load steps do not click
const FADE_IN_S := 1.5 # the gear whine rises over this time after the engine fires
const IMPACT_GAIN := 0.12 # gear tooth impact level, before the load factor
const IMPACT_DECAY_S := 0.0008 # each tooth impact is a click that dies in about 1 ms
const HARMONIC_2ND_GAIN := 0.08 # 2nd order torsional harmonic, relative to the whine
const SEED := 7141

var _rng := RandomNumberGenerator.new()
var _lp := 0.0 # low-pass state of the rumble noise
var _rumble_res := 0.0 # resonator state: last output
var _rumble_res2 := 0.0 # resonator state: output before that
var _phase := 0.0 # whine phase in cycles, carried between blocks
var _freq := 0.0 # smoothed whine frequency, Hz
var _amp := 0.0 # smoothed whine amplitude
var _impact := 0.0 # tooth impact envelope: 1 when a tooth passes, decays until the next
var _teeth := CRANK_GEAR_TEETH # crank pinion teeth, from the engine spec when available


func _init() -> void:
	reset()


func configure(spec: EngineSpec) -> void:
	_teeth = maxf(spec.primary_crank_teeth, 1.0)
	reset()


# Clears every state, for an engine restart. The seed is fixed so a render is the same every time.
func reset() -> void:
	_rng.seed = SEED
	_lp = 0.0
	_rumble_res = 0.0
	_rumble_res2 = 0.0
	_phase = 0.0
	_freq = 0.0
	_amp = 0.0
	_impact = 0.0


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
	var rpm_scale := pow(clampf(c.rpm / 12000.0, 0.0, 1.0), 0.7)
	var rumble := rpm_scale * RUMBLE_GAIN

	# Two-pole resonator at a fixed structure/bearing mode. The rotor orders sweep past it with rpm; the mode itself does not.
	var f_res := minf(RUMBLE_RESONANCE_HZ, SoundLayer.RATE * 0.45)
	var r := exp(-PI * RESONANCE_BW_HZ / SoundLayer.RATE)
	var res_c := 2.0 * r * cos(TAU * f_res / SoundLayer.RATE)
	var res_gain := rpm_scale * RUMBLE_RESONANCE_GAIN * (1.0 - r)
	var imp_decay := exp(-1.0 / (SoundLayer.RATE * IMPACT_DECAY_S))

	# The mesh tone is the crank gear's tooth-passing rate: crank rpm / 60 times the crank gear's teeth. The primary ratio is
	# already in the basket's speed, so it is not applied again. 23 teeth is an estimate for a crank pinion, not a measured value.
	var target_f := c.rpm / 60.0 * _teeth
	while target_f > WHINE_MAX_HZ:
		target_f *= 0.5
	# A primary gear is still loaded by its own inertia and the oil at idle. Keep a floor so the mesh is present
	# there, then let the torque-dependent part take over under load.
	var load := clampf(c.load, 0.0, 1.0)
	var load_factor := 0.2 + 0.8 * load * load
	var fade := _fade_in(c.fire_time) * c.gear_whine
	var target_amp := WHINE_GAIN * load_factor * fade
	var impact_level := IMPACT_GAIN * load_factor * fade

	# Per-sample glide toward the targets; a one-pole with the 20 ms time constant.
	var k := 1.0 - exp(-1.0 / (SoundLayer.RATE * SMOOTH_S))
	for i in frames:
		var x := _rng.randf_range(-1.0, 1.0)
		_lp += a * (x - _lp)
		var res := x * (1.0 - r) + res_c * _rumble_res - r * r * _rumble_res2
		_rumble_res2 = _rumble_res
		_rumble_res = res
		_freq += (target_f - _freq) * k
		_amp += (target_amp - _amp) * k
		var prev_phase := _phase
		_phase = fmod(_phase + _freq / SoundLayer.RATE, 1.0)
		if _phase < prev_phase: # the mesh wrapped, so one tooth passed: one click
			_impact = 1.0
		# a gear mesh is a pure tone at its tooth-passing rate, plus a 2nd harmonic from torsional twist
		var tone := sin(TAU * _phase) + HARMONIC_2ND_GAIN * sin(TAU * 2.0 * _phase)
		var click := _impact * x * impact_level
		_impact *= imp_decay
		out[i] = float(_lp * rumble + res * res_gain + tone * _amp + click)
	return out
