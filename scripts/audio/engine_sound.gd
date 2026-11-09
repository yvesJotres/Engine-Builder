class_name EngineSound
extends AudioStreamPlayer3D

# Tail volume-flow from ExhaustGas is the source. Header length and backpressure are already in that flow.
# The playback chain follows engine-sim's synthesizer: remove the standing flow, take the pulse and
# its edge, add a little colored noise for rasp, then convolve a recorded muffler impulse response.
# The convolution runs at 16 kHz on the first 32 ms of the recording, which is the canister, not the room.
# Intake noise is mixed in at low level for realism at idle/part-throttle.

const RATE := 44100.0
const BODY_RATE := 16000.0
const TAPS := 128 # direct pulse edge retains high-frequency detail; shorter tail keeps live playback smooth
const BASE_FLOW_SCALE := 28.0 # calibrated for ~150 cc; scaled by displacement in setup()
const EDGE_MIX := 0.55 # share of the sample-to-sample change; the rest is the flow
const NOISE_MIX := 0.22 # rasp on the pulse. Most of the sample is the pulse itself
const WET := 0.84
const SMOOTH_HZ := 1900.0
const DC_HZ := 10.0
const NOISE_HZ := 2000.0
const LEVEL_TARGET := 0.4
const LEVEL_DECAY := 0.9996
const LEVEL_FOLLOW := 0.04
const LEVEL_MIN := 0.04
const LEVEL_MAX := 5.0
const BACKFIRE_DURATION := 0.02
const IR_MUFFLER := "res://assets/ir/mild_exhaust.wav"
const IR_OPEN := "res://assets/ir/sharp_01.wav"
const INTAKE_MIX := 0.15 # intake noise level relative to exhaust
const INTAKE_HZ := 1400.0 # the intake honk, brighter than the muffled exhaust body
# The intake runner rings as a Helmholtz resonator. A real air filter and throttle body damp it; the model's runner is
# too lightly damped, so the ring is a clear high tone. This cut is that missing damping, applied to the sound only.
const RESONANCE_CUT_DB := 0.0 # dB removed at the runner resonance: 0 leaves the sound unchanged (a deeper cut made the firing pulses stand out as pings)
const RESONANCE_Q := 1.5 # width of the cut: lower is broader

static var _kernels := {}

var starved := false
var rpm := 900.0
var audio_enabled := true # the convolution runs only while something is listening

var _flow := PackedFloat32Array()
var _intake_flow := PackedFloat32Array()
var _read := 0
var _intake_read := 0
var _q := 0.0
var _intake_q := 0.0
var _intake_lp := 0.0
var _intake_dc := 0.0
var _lp := 0.0
var _dc := 0.0
var _edge_mix := EDGE_MIX
var _noise_mix := NOISE_MIX
var _rasp_scale := 1.0 # from the panel: multiplies the rasp noise level
var _intake_scale := 1.0 # from the panel: multiplies the intake noise level
var _lambda := 1.0
var _egt_c := 400.0
var _back_pa := 101325.0
var _prev_f := 0.0
var _nz := 0.0
var _rng := 1
var _lp_a := 0.2
var _dc_a := 0.001
var _nz_a := 0.2
var _intake_a := 0.0
# Peaking cut at the runner resonance (biquad coefficients and its two-sample history)
var _nb0 := 1.0
var _nb1 := 0.0
var _nb2 := 0.0
var _na1 := 0.0
var _na2 := 0.0
var _nx1 := 0.0
var _nx2 := 0.0
var _ny1 := 0.0
var _ny2 := 0.0
var _ir := PackedFloat32Array()
var _hist := PackedFloat32Array()
var _hp := 0
var _bucket := 0.0
var _bucket_n := 0
var _since := 0.0
var _mix_prev := 0.0
var _mix_curr := 0.0
var _peak := 0.2
var _gain := 1.0
var _delay := PackedFloat32Array()
var _dp := 0
var _flow_scale := BASE_FLOW_SCALE
var _last_sample := 0.0
var compressor_load := 0.0
var _compressor_phase := 0.0
var drive := SoundContext.new() # what the sound layers need to know: the game fills it every frame
var _layers := LayerBank.new() # valve tick, bottom end, driveline, turbo and knock, added to the mix


func setup(_spec: EngineSpec, layout: ExhaustLayout = null) -> void:
	stop()
	_flow = PackedFloat32Array()
	_intake_flow = PackedFloat32Array()
	_read = 0
	_intake_read = 0
	_q = 0.0
	_intake_q = 0.0
	_intake_lp = 0.0
	_intake_dc = 0.0
	_lp = 0.0
	_dc = 0.0
	_edge_mix = EDGE_MIX
	_noise_mix = NOISE_MIX
	_lambda = 1.0
	_egt_c = 400.0
	_back_pa = 101325.0
	_prev_f = 0.0
	_nz = 0.0
	_rng = 1
	_hp = 0
	_bucket = 0.0
	_bucket_n = 0
	_since = 0.0
	_mix_prev = 0.0
	_mix_curr = 0.0
	_peak = 0.2
	_gain = 1.0
	_dp = 0
	_last_sample = 0.0
	_compressor_phase = 0.0
	starved = false
	_lp_a = _alpha(SMOOTH_HZ)
	_dc_a = _alpha(DC_HZ)
	_nz_a = _alpha(NOISE_HZ)
	_intake_a = _alpha(INTAKE_HZ)
	_set_resonance_cut(_spec)
	_layers = LayerBank.standard(OS.has_feature("mobile"))
	_layers.configure(_spec)
	apply_levels(_spec) # the bank exists now, so the panel levels can scale it
	# The leveler sets the loudness. Volume flow already grows with displacement, and scaling by it
	# again pushed a large engine past the clipper, which turned the firing ripple into a buzz.
	_flow_scale = BASE_FLOW_SCALE
	_ir = _kernel(_ir_path(_spec, layout))
	_hist = PackedFloat32Array()
	_hist.resize(TAPS)
	_delay = PackedFloat32Array()
	_delay.resize(32)
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.25
	stream = gen
	# The camera sits about 11 scene units off the engine (1 unit = 10 cm). unit_size keeps that seat loud
	# and lets a longer camera pull the tailpipe away.
	unit_size = 18.0
	max_distance = 80.0
	attenuation_filter_cutoff_hz = 5000.0


func push_flow(samples: PackedFloat32Array) -> void:
	if samples.is_empty():
		return
	if _read > 4096:
		_flow = _flow.slice(_read)
		_read = 0
	var base := _flow.size()
	_flow.resize(base + samples.size())
	for i in samples.size():
		_flow[base + i] = samples[i]


func push_intake_flow(samples: PackedFloat32Array) -> void:
	if samples.is_empty():
		return
	if _intake_read > 4096:
		_intake_flow = _intake_flow.slice(_intake_read)
		_intake_read = 0
	var base := _intake_flow.size()
	_intake_flow.resize(base + samples.size())
	for i in samples.size():
		_intake_flow[base + i] = samples[i]


func set_cylinders(_cylinders: Array[Cylinder]) -> void:
	pass


# Lambda, exhaust temperature and the pressure at the exhaust valve. They nudge rasp, brightness and edge.
# A lambda of 99 means the cylinder has not burned yet, so it is ignored.
# The sound levels from the panel. Called at setup and whenever the panel changes, so the sliders work while the engine runs.
func apply_levels(spec: EngineSpec) -> void:
	_rasp_scale = spec.sound_rasp
	_intake_scale = spec.sound_intake
	if _layers != null:
		_layers.set_scale("valvetrain", spec.sound_valvetrain)
		_layers.set_scale("mechanical", spec.sound_mechanical)
		_layers.set_scale("driveline", spec.sound_driveline)
		_layers.set_scale("turbo", spec.sound_turbo)
		_layers.set_scale("knock", spec.sound_knock)


func set_conditions(lambda: float, egt_c: float, backpressure_pa: float) -> void:
	if lambda < 50.0:
		_lambda = lerpf(_lambda, lambda, 0.2)
	_egt_c = lerpf(_egt_c, egt_c, 0.1)
	_back_pa = lerpf(_back_pa, backpressure_pa, 0.2)
	var hot := clampf((_egt_c - 250.0) / 550.0, 0.0, 1.0)
	var stuffed := clampf((_back_pa - 101325.0) / 30000.0, 0.0, 1.0)
	var lean := clampf((_lambda - 0.9) / 0.25, 0.0, 1.0)
	_lp_a = _alpha(lerpf(1500.0, 2600.0, hot) * lerpf(1.0, 0.7, stuffed))
	_edge_mix = lerpf(EDGE_MIX, EDGE_MIX * 0.6, stuffed)
	_noise_mix = lerpf(0.14, 0.34, lean) * _rasp_scale


func render(frames: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(frames)
	if not audio_enabled or frames <= 0:
		return out
	var step := RATE / BODY_RATE
	var ir := _ir
	var layer_mix := _layers.render(frames, drive)
	var hist := _hist
	var taps := ir.size()
	for i in frames:
		_bucket += _excite()
		var intake := _intake_sample()
		_bucket_n += 1
		_since += 1.0
		if _since >= step:
			_since -= step
			var body := _bucket / float(_bucket_n)
			_bucket = 0.0
			_bucket_n = 0
			hist[_hp] = body
			var wet := 0.0
			for k in taps:
				var at := _hp - k
				if at < 0:
					at += TAPS
				wet += ir[k] * hist[at]
			_hp += 1
			if _hp >= TAPS:
				_hp = 0
			_mix_prev = _mix_curr
			# Keep a small direct edge alongside the shorter live convolution tail.
			_mix_curr = wet * WET + body * (1.0 - WET) + body * 0.40
		# Estimated electric compressor whine, following load rather than crank speed.
		var whine := 0.0
		if compressor_load > 0.0:
			_compressor_phase = fposmod(_compressor_phase + TAU * (900.0 + 2600.0 * compressor_load) / RATE, TAU)
			whine = sin(_compressor_phase) * compressor_load * 0.012
		var sample := _shape(lerpf(_mix_prev, _mix_curr, _since / step) + intake + whine + layer_mix[i])
		_delay[_dp] = sample
		var side := _delay[(_dp + 18) % 32]
		_dp = (_dp + 1) % 32
		out[i] = Vector2(sample, sample * 0.7 + side * 0.3)
	_hist = hist
	return out


# With no gas solver bound, a backfire is a short volume-flow pulse so the pop is still audible.
# When ExhaustGas is running, the energy is already in the pipe and this does not add a second one.
func backfire(energy_j: float, _cylinder_index: int = 0) -> void:
	if energy_j <= 0.0:
		return
	var count := maxi(2, roundi(BACKFIRE_DURATION * RATE))
	var amp := 0.016 * sqrt(energy_j)
	var pulse := PackedFloat32Array()
	pulse.resize(count)
	for i in count:
		pulse[i] = _q + amp * sin(PI * float(i) / float(count))
	push_flow(pulse)


func clear_pending() -> void:
	stop()
	_flow = PackedFloat32Array()
	_intake_flow = PackedFloat32Array()
	_read = 0
	_intake_read = 0
	_q = 0.0
	_intake_q = 0.0
	_intake_lp = 0.0
	_intake_dc = 0.0
	_lp = 0.0
	_dc = 0.0
	_prev_f = 0.0
	_last_sample = 0.0
	_hist.fill(0.0)
	_delay.fill(0.0)
	_hp = 0
	_dp = 0
	_bucket = 0.0
	_bucket_n = 0
	_since = 0.0
	_nz = 0.0
	_mix_prev = 0.0
	_mix_curr = 0.0
	starved = false
	_layers.reset()


func _process(_delta: float) -> void:
	if not audio_enabled or stream == null or not playing or stream_paused:
		return
	var pb := get_stream_playback() as AudioStreamGeneratorPlayback
	if pb == null:
		return
	var room := pb.get_frames_available()
	starved = room > int(stream.buffer_length * RATE * 0.9)
	if room > 0:
		pb.push_buffer(render(room))


func _excite() -> float:
	var fresh := false
	if _read < _flow.size():
		fresh = true
		_q = _flow[_read]
		_read += 1
		_nz += _nz_a * (_white() - _nz)
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
	var air := _noise_mix * _nz + (1.0 - _noise_mix) if fresh else 1.0
	_last_sample = edge * _edge_mix + flow * air * (1.0 - _edge_mix)
	return _last_sample


# The intake is not run through the muffler. It is the valve flow itself, duller than a raw pulse and quieter than the tail.
func _intake_sample() -> float:
	var fresh := false
	if _intake_read < _intake_flow.size():
		fresh = true
		_intake_q = _intake_flow[_intake_read]
		_intake_read += 1
	elif not _intake_flow.is_empty():
		_intake_q += (0.0 - _intake_q) * 0.02
	else:
		_intake_q = 0.0
	_intake_lp += _intake_a * (_intake_q - _intake_lp)
	_intake_dc += _dc_a * (_intake_lp - _intake_dc)
	var flow := _resonance_cut((_intake_lp - _intake_dc) * _flow_scale * INTAKE_MIX * _intake_scale)
	var air := _noise_mix * _nz + (1.0 - _noise_mix) if fresh else 1.0
	return flow * air


func _shape(sample: float) -> float:
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


# Helmholtz frequency of the intake runner: f = c / (2 pi) * sqrt(A / (L V)), with the same runner and port values as the sim
func _set_resonance_cut(spec: EngineSpec) -> void:
	var length := spec.runner_length_m if spec != null and spec.runner_length_m > 0.0 else 0.25
	var f0 := 343.0 / TAU * sqrt(Cylinder.RUNNER_AREA / (length * Cylinder.PORT_VOLUME))
	var a := pow(10.0, RESONANCE_CUT_DB / 40.0)
	var w0 := TAU * f0 / RATE
	var alpha := sin(w0) / (2.0 * RESONANCE_Q)
	var b0 := 1.0 + alpha * a
	var b1 := -2.0 * cos(w0)
	var b2 := 1.0 - alpha * a
	var a0 := 1.0 + alpha / a
	var a1 := -2.0 * cos(w0)
	var a2 := 1.0 - alpha / a
	_nb0 = b0 / a0
	_nb1 = b1 / a0
	_nb2 = b2 / a0
	_na1 = a1 / a0
	_na2 = a2 / a0
	_nx1 = 0.0
	_nx2 = 0.0
	_ny1 = 0.0
	_ny2 = 0.0


func _resonance_cut(x: float) -> float:
	var y := _nb0 * x + _nb1 * _nx1 + _nb2 * _nx2 - _na1 * _ny1 - _na2 * _ny2
	_nx2 = _nx1
	_nx1 = x
	_ny2 = _ny1
	_ny1 = y
	return y


func _alpha(cutoff: float) -> float:
	var rc := 1.0 / (TAU * cutoff)
	var dt := 1.0 / RATE
	return dt / (rc + dt)


func _ir_path(spec: EngineSpec, layout: ExhaustLayout) -> String:
	# Per-preset IR override takes priority
	if spec.exhaust_ir_path != "":
		return spec.exhaust_ir_path
	if layout == null:
		return IR_MUFFLER
	for pipe in layout.pipes:
		if pipe.kind == "muffler":
			return IR_MUFFLER
	return IR_OPEN


static func _kernel(path: String) -> PackedFloat32Array:
	if _kernels.has(path):
		return _kernels[path]
	var pcm := _read_wav(path)
	var kernel := PackedFloat32Array()
	kernel.resize(TAPS)
	if pcm.is_empty():
		for i in TAPS:
			var t := float(i) / BODY_RATE
			kernel[i] = exp(-t * 90.0) * sin(TAU * 240.0 * t)
	else:
		var keep := mini(pcm.size(), int(0.032 * RATE))
		keep = maxi(keep, 1)
		for i in TAPS:
			var start := float(i) * float(keep) / float(TAPS)
			var span_end := float(i + 1) * float(keep) / float(TAPS)
			var acc := 0.0
			var n := 0
			var last := mini(ceili(span_end), keep)
			for j in range(int(start), maxi(last, int(start) + 1)):
				acc += pcm[j]
				n += 1
			kernel[i] = acc / float(n)
	var weight := 0.0
	for i in TAPS:
		weight += absf(kernel[i])
	if weight > 0.0:
		for i in TAPS:
			kernel[i] /= weight
	_kernels[path] = kernel
	return kernel


static func _read_wav(path: String) -> PackedFloat32Array:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return PackedFloat32Array()
	file.get_buffer(12)
	var pcm := PackedByteArray()
	var bits := 16
	while file.get_position() + 8 <= file.get_length():
		var chunk := file.get_buffer(4).get_string_from_ascii()
		var size := file.get_32()
		if chunk == "fmt ":
			file.get_16()
			file.get_16()
			file.get_32()
			file.get_32()
			file.get_16()
			bits = file.get_16()
			if size > 16:
				file.seek(file.get_position() + size - 16)
		elif chunk == "data":
			pcm = file.get_buffer(size)
			break
		else:
			file.seek(file.get_position() + size)
	file.close()
	if bits != 16 or pcm.size() < 2:
		return PackedFloat32Array()
	var count := pcm.size() >> 1
	var samples := PackedFloat32Array()
	samples.resize(count)
	var end := 0
	for i in count:
		var value := pcm[i * 2] | (pcm[i * 2 + 1] << 8)
		if value >= 32768:
			value -= 65536
		samples[i] = float(value)
		if abs(value) > 100:
			end = i + 1
	end = clampi(end, 0, mini(count, 10000))
	if end == 0:
		return PackedFloat32Array()
	return samples.slice(0, end)
