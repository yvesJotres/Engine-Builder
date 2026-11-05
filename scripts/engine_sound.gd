class_name EngineSound
extends AudioStreamPlayer

# Exhaust sound from a waveguide of the drawn pipes (ExhaustLayout). Each cylinder's blowdown pulse enters its own primary
# pipe; sound travels down and back along every pipe, scatters where pipes join or change width, reflects off the closed
# port end and off the open tail, and what leaves the tail is what you hear. The pipe lengths set the pitch and the
# resonances, so a longer header or a bigger muffler really sounds different.

const RATE := 44100.0
const WG_RATE := 22050.0 # the pipes run at half the output rate (a 0.5 m pipe is still 22 samples), then are upsampled
const SOUND_SPEED := 500.0 # m/s in the hot exhaust gas, estimate; the real speed rises with load and falls along the pipe
const CLOSED_END := 0.85 # reflection at the port end while the exhaust valve is shut, estimate
const OPEN_END := 0.97 # open tail end reflects with the sign flipped, the rest leaves as sound
const OPEN_END_LP := 0.7 # tail-end low-pass per pipe sample: a narrow mouth lets less top end out
const BLOWDOWN_DEG := 120.0 # crank angle over which the burnt gas rushes out when the valve opens
const IR_PATH := "res://assets/ir/minimal_muffling_03.wav" # an engine-sim exhaust response, see THIRD_PARTY.md
const IR_DECIMATION := 4 # the response runs at 11 kHz, a quarter of the output rate: the same 23 ms, a quarter of the work
const IR_LEVEL := 0.65 # the response adds about 3.8 dB at unit energy, so this keeps the loudness of the dry sound
const IR_TAPS_MAX := 256 # taps after decimation, about 98% of the response's energy
const CLICK_SAMPLES := 88 # 2 ms, the length of the spark crack
const CLICK_LEVEL := 0.02 # peak of the crack at full fuel burn; it happens inside the engine, so it stays quiet
const CLICK_DECAY := 6.0 # how fast the crack dies away
const POP_SAMPLES := 1100 # 25 ms, the length of a backfire pop
const POP_LEVEL := 0.6 # peak of a full backfire, fed into the exhaust response so the pipes shape it
const POP_FULL_J := 250.0 # J of unlit fuel burning in the exhaust for a full pop, estimate: about one cylinder's charge at idle
const POP_DECAY := 4.0 # how fast the pop dies away
const OUTPUT_GAIN := 75.0 # calibrated so the loudness matches the earlier single-resonator exhaust (0.30 rms at 6,000 rpm, one cylinder)

var starved := false # true when the sound ran out of audio since the last frame
var rpm := 900.0
var firing := true # exhaust pulses only come from burning mixture, so the limiter cut is quiet
var energy := 1.0 # 0 to 1: exhaust energy from the intake charge, so loudness follows the air
var lowpass := 0.5 # exhaust low-pass per sample: higher lets more top end through
var bass_gain := 0.0 # extra low band (below about 140 Hz) added on top of the exhaust
var high_gain := 0.0 # extra band above about 1 kHz added on top of the exhaust

var _cycle := 0.0 # unwrapped crank angle, deg
var _fire: Array[float] = []
var _lp := 0.0
var _bass_lp := 0.0
var _mid_lp := 0.0
var _smooth_energy := 1.0

# Waveguide state. Pipe i owns _len[i] samples of delay in each direction, stored from _off[i] in the flat buffers.
var _n := 0 # pipes
var _off := PackedInt32Array()
var _len := PackedInt32Array()
var _pos := PackedInt32Array() # where each delay line reads and writes next
var _buf_f := PackedFloat32Array() # waves travelling downstream (toward the tail)
var _buf_b := PackedFloat32Array() # waves travelling back upstream
var _admit := PackedFloat32Array() # cross-section, sets how waves split at a junction
var _sum_admit := PackedFloat32Array() # this pipe plus everything joining at its upstream end
var _gain := PackedFloat32Array() # amplitude kept after one trip along the pipe
var _feeders: Array = [] # per pipe, PackedInt32Array of the pipes joining at its upstream end
var _prim := PackedInt32Array() # pipe index of each cylinder's primary
var _arr_f := PackedFloat32Array() # scratch: wave arriving at each pipe's downstream end
var _arr_b := PackedFloat32Array() # scratch: wave arriving at each pipe's upstream end
var _out_f := PackedFloat32Array()
var _out_b := PackedFloat32Array()
var _inject := PackedFloat32Array() # blowdown pressure entering each pipe this sample
var _p_age := PackedFloat32Array() # per cylinder: samples into the current blowdown, -1 when idle
var _p_len := PackedFloat32Array()
var _p_amp := PackedFloat32Array()
var _tail_lp := 0.0
var _u_prev := 0.0 # tail flow one sample ago, the radiated sound follows its change
var _wg_prev := 0.0
var _wg_cur := 0.0
var _odd := false


var _click_left := 0 # samples left in the current spark crack
var _click_level := 0.0
var _pop_left := 0 # samples left in the current backfire pop
var _pop_level := 0.0 # peak of the current backfire, from the energy that burned in the exhaust
var _click_prev := 0.0
var _ir := PackedFloat32Array() # exhaust impulse response, decimated, scaled to unit energy
var _hist := PackedFloat32Array() # the last few decimated exhaust samples, a ring buffer
var _hist_pos := 0
var _acc := 0.0 # sum of the output samples since the last decimated sample
var _phase := 0
var _wet := 0.0
var _wet_prev := 0.0


# Loads the exhaust impulse response once. If the file is missing or not 16-bit 44.1 kHz, the sound stays dry.
func _ready() -> void:
	var wav := load(IR_PATH) as AudioStreamWAV
	if wav == null or wav.format != AudioStreamWAV.FORMAT_16_BITS or wav.mix_rate != int(RATE):
		return
	var blocks := mini(IR_TAPS_MAX, wav.data.size() / 2 / IR_DECIMATION)
	_ir.resize(blocks)
	var energy := 0.0
	for b in blocks:
		# average each block of samples: a simple low-pass before the decimation
		var sum := 0.0
		for k in IR_DECIMATION:
			sum += wav.data.decode_s16((b * IR_DECIMATION + k) * 2)
		_ir[b] = sum / IR_DECIMATION / 32768.0
		energy += _ir[b] * _ir[b]
	if energy > 0.0:
		var gain := IR_LEVEL / sqrt(energy)
		for b in blocks:
			_ir[b] *= gain
	_hist.resize(blocks)
	_hist.fill(0.0)


# Runs the exhaust through the impulse response. Every IR_DECIMATION samples it does one multiply-add per tap, and the
# result between those samples is interpolated. Returns the input unchanged when no response is loaded.
func _convolve(x: float) -> float:
	if _ir.is_empty():
		return x
	_acc += x
	_phase += 1
	if _phase == IR_DECIMATION:
		_phase = 0
		_hist[_hist_pos] = _acc / IR_DECIMATION
		_acc = 0.0
		var y := 0.0
		var idx := _hist_pos
		for k in _ir.size():
			y += _ir[k] * _hist[idx]
			idx = idx - 1 if idx > 0 else _hist.size() - 1
		_hist_pos = (_hist_pos + 1) % _hist.size()
		_wet_prev = _wet
		_wet = y
	return lerpf(_wet_prev, _wet, float(_phase) / IR_DECIMATION)


func setup(spec: EngineSpec, layout: ExhaustLayout = null) -> void:
	stop()
	_cycle = 0.0
	_fire = FiringOrders.for_spec(spec)
	if layout == null:
		layout = ExhaustLayout.build(spec)
	_build_pipes(layout)
	_lp = 0.0
	_bass_lp = 0.0
	_mid_lp = 0.0
	_tail_lp = 0.0
	_u_prev = 0.0
	_wg_prev = 0.0
	_wg_cur = 0.0
	_odd = false
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.25 # a phone can take longer than 0.1 s to fill a frame, so a shorter buffer runs dry and goes silent
	stream = gen


func _build_pipes(layout: ExhaustLayout) -> void:
	_n = layout.pipes.size()
	_off.resize(_n)
	_len.resize(_n)
	_pos.resize(_n)
	_admit.resize(_n)
	_sum_admit.resize(_n)
	_gain.resize(_n)
	_arr_f.resize(_n)
	_arr_b.resize(_n)
	_out_f.resize(_n)
	_out_b.resize(_n)
	_inject.resize(_n)
	_inject.fill(0.0)
	_feeders.clear()
	_prim.clear()
	var total := 0
	for i in _n:
		var pipe := layout.pipes[i]
		var d := maxi(2, roundi(pipe.length_m() / SOUND_SPEED * WG_RATE))
		_off[i] = total
		_len[i] = d
		_pos[i] = 0
		total += d
		_admit[i] = pipe.area_m2() * 1.0e4 # cm², only the ratios matter
		_gain[i] = exp(-pipe.loss * pipe.length_m())
		_feeders.append(PackedInt32Array(pipe.feeders))
		if pipe.cyl >= 0:
			_prim.append(i)
	for i in _n:
		var s: float = _admit[i]
		for f in _feeders[i]:
			s += _admit[f]
		_sum_admit[i] = s
	_buf_f.resize(total)
	_buf_f.fill(0.0)
	_buf_b.resize(total)
	_buf_b.fill(0.0)
	var cyls := _prim.size()
	_p_age.resize(cyls)
	_p_age.fill(-1.0)
	_p_len.resize(cyls)
	_p_amp.resize(cyls)


func _process(_delta: float) -> void:
	if not playing:
		return
	var pb := get_stream_playback() as AudioStreamGeneratorPlayback
	# fill the player's free space; the synthesis runs here, on the main thread
	var room := pb.get_frames_available()
	# nearly empty buffer = the sound ran dry since last frame (shown on screen as "Sound: starved")
	starved = room > int(stream.buffer_length * RATE * 0.9)
	for frame in render(room):
		pb.push_frame(frame)


# A backfire happened: pop the exhaust, louder with more unlit fuel burning in it.
func backfire(energy_j: float) -> void:
	_pop_level = POP_LEVEL * clampf(energy_j / POP_FULL_J, 0.0, 1.0)
	_pop_left = POP_SAMPLES


# Makes the next `frames` samples of exhaust sound, as stereo frames.
func render(frames: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var step := rpm * 6.0 / RATE # crank deg per sample
	var blow_len := BLOWDOWN_DEG / (6.0 * maxf(rpm, 1.0)) * WG_RATE # blowdown length in pipe samples
	var cyls := _prim.size()
	# energy comes from per-frame fuel flow, which jumps with each burn; smooth it or the note stutters
	_smooth_energy = lerpf(_smooth_energy, energy, 0.1)
	for _i in frames:
		var prev := _cycle
		_cycle += step
		# the exhaust valve opens EXHAUST_OPEN degrees after the cylinder fires, and the burnt gas rushes into its primary
		for c in cyls:
			if firing and FiringOrders.fired_between(prev, _cycle, _fire[c] + Cylinder.EXHAUST_OPEN):
				_p_age[c] = 0.0
				_p_len[c] = blow_len
				_p_amp[c] = _smooth_energy / sqrt(cyls)
		# the spark jumps the plug gap a little before each firing: a short electrical crack, scaled by the fuel burned
		for c in cyls:
			if firing and FiringOrders.fired_between(prev, _cycle, _fire[c] - EngineAir.spark_advance_deg(rpm)):
				_click_left = CLICK_SAMPLES
				_click_level = CLICK_LEVEL * _smooth_energy
		var click := 0.0
		if _click_left > 0:
			# noise differenced once to make it bright, decaying over the 2 ms
			var noise := randf_range(-1.0, 1.0)
			var age := float(CLICK_SAMPLES - _click_left) / CLICK_SAMPLES
			click = _click_level * (noise - _click_prev) * exp(-age * CLICK_DECAY)
			_click_prev = noise
			_click_left -= 1
		# a backfire: a noise burst into the exhaust, decaying over 25 ms, shaped by the pipes like the rest of the note
		var pop := 0.0
		if _pop_left > 0:
			var age_p := float(POP_SAMPLES - _pop_left) / POP_SAMPLES
			pop = _pop_level * randf_range(-1.0, 1.0) * exp(-age_p * POP_DECAY)
			_pop_left -= 1
		var s := clampf(_convolve(_sample() + pop) + click, -1.0, 1.0)
		out.append(Vector2(s, s))
	return out


func _sample() -> float:
	# the pipes run at half rate: a new pipe sample every second output sample, the one between is the average
	_odd = not _odd
	if _odd:
		_wg_prev = _wg_cur
		_wg_cur = _wg_step()
	var out := _wg_prev if _odd else 0.5 * (_wg_prev + _wg_cur)
	out *= OUTPUT_GAIN
	# exhaust low-pass, then the extra bass and top bands
	_bass_lp += 0.02 * (out - _bass_lp)
	_mid_lp += 0.15 * (out - _mid_lp)
	out += bass_gain * _bass_lp + high_gain * (out - _mid_lp)
	# muffling eases off as rpm rises: full top end from 3,000 rpm up, a quarter of it at idle
	_lp += lowpass * clampf(rpm / 3000.0, 0.25, 1.0) * (out * 0.5 - _lp)
	return clampf(_lp, -1.0, 1.0)


# One step of every pipe. Reads what reaches each end, resolves the junctions, writes what leaves.
func _wg_step() -> float:
	# blowdown pulses: a half sine of pressure into the primary pipe
	for c in _prim.size():
		var age := _p_age[c]
		if age >= 0.0:
			if age < _p_len[c]:
				_inject[_prim[c]] = _p_amp[c] * sin(PI * age / _p_len[c])
				_p_age[c] = age + 1.0
			else:
				_p_age[c] = -1.0
				_inject[_prim[c]] = 0.0
	for i in _n:
		var at := _off[i] + _pos[i]
		_arr_f[i] = _buf_f[at]
		_arr_b[i] = _buf_b[at]
	for j in _n:
		var feeders: PackedInt32Array = _feeders[j]
		if feeders.is_empty():
			# the port end: the shut valve reflects, and the blowdown adds to it
			_out_f[j] = CLOSED_END * _arr_b[j] + _inject[j]
		else:
			# a junction: one shared pressure, every pipe takes its share of the incoming waves
			var flow := _admit[j] * _arr_b[j]
			for f in feeders:
				flow += _admit[f] * _arr_f[f]
			var p := 2.0 * flow / _sum_admit[j]
			_out_f[j] = p - _arr_b[j]
			for f in feeders:
				_out_b[f] = p - _arr_f[f]
	var last := _n - 1
	# the open tail: the wave reflects with its sign flipped and a duller tone, the rest is sound
	_tail_lp += OPEN_END_LP * (_arr_f[last] - _tail_lp)
	_out_b[last] = -OPEN_END * _tail_lp
	var u := _arr_f[last] - _out_b[last]
	var sound := u - _u_prev
	_u_prev = u
	for i in _n:
		var at := _off[i] + _pos[i]
		_buf_f[at] = _out_f[i] * _gain[i]
		_buf_b[at] = _out_b[i] * _gain[i]
		_pos[i] = (_pos[i] + 1) % _len[i]
	return sound
