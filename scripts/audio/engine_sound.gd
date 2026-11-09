class_name EngineSound
extends AudioStreamPlayer3D

# Tail volume-flow from ExhaustGas is the source. Header length and backpressure are already in that flow.
# The exhaust pulse (edge, rasp, level) is made in ExhaustSound; this file convolves it with a recorded muffler impulse
# response. The convolution runs at 16 kHz on the first 32 ms of the recording, which is the canister, not the room.
# Intake noise is mixed in at low level for realism at idle/part-throttle.

const RATE := 44100.0
const BODY_RATE := 16000.0
const TAPS := 128 # direct pulse edge retains high-frequency detail; shorter tail keeps live playback smooth
const WET := 0.84
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
var exh := ExhaustSound.new() # the exhaust pulse: edge, rasp and level

var _flow := PackedFloat32Array()
var _intake_flow := PackedFloat32Array()
var _intake_read := 0
var _intake_q := 0.0
var _intake_lp := 0.0
var _intake_dc := 0.0
var _dc_a := 0.001
var _rasp_scale := 1.0 # from the panel: multiplies the rasp noise level
var _intake_scale := 1.0 # from the panel: multiplies the intake noise level
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
var _flow_scale := ExhaustSound.BASE_FLOW_SCALE
var _delay := PackedFloat32Array()
var _dp := 0
var compressor_load := 0.0
var _compressor_phase := 0.0
var drive := SoundContext.new() # what the sound layers need to know: the game fills it every frame
var _layers := LayerBank.new() # valve tick, bottom end, driveline, turbo and knock, added to the mix


func setup(_spec: EngineSpec, layout: ExhaustLayout = null) -> void:
	stop()
	_flow = PackedFloat32Array()
	_intake_flow = PackedFloat32Array()
	_intake_read = 0
	_intake_q = 0.0
	_intake_lp = 0.0
	_intake_dc = 0.0
	_hp = 0
	_bucket = 0.0
	_bucket_n = 0
	_since = 0.0
	_mix_prev = 0.0
	_mix_curr = 0.0
	_dp = 0
	_compressor_phase = 0.0
	starved = false
	exh.reset()
	_dc_a = ExhaustSound.alpha(ExhaustSound.DC_HZ)
	_intake_a = ExhaustSound.alpha(INTAKE_HZ)
	_set_resonance_cut(_spec)
	_layers = LayerBank.standard(OS.has_feature("mobile"))
	_layers.configure(_spec)
	apply_levels(_spec) # the bank exists now, so the panel levels can scale it
	# The leveler sets the loudness. Volume flow already grows with displacement, and scaling by it
	# again pushed a large engine past the clipper, which turned the firing ripple into a buzz.
	_flow_scale = ExhaustSound.BASE_FLOW_SCALE
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
	exh.push(samples)


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
	exh.set_conditions(lambda, egt_c, backpressure_pa, _rasp_scale)


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
		_bucket += exh.excite()
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
		var sample := exh.shape(lerpf(_mix_prev, _mix_curr, _since / step) + intake + whine + layer_mix[i])
		_delay[_dp] = sample
		var side := _delay[(_dp + 18) % 32]
		_dp = (_dp + 1) % 32
		out[i] = Vector2(sample, sample * 0.7 + side * 0.3)
	_hist = hist
	if exh.starved:
		starved = true
		exh.starved = false
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
		pulse[i] = exh._q + amp * sin(PI * float(i) / float(count))
	push_flow(pulse)


func clear_pending() -> void:
	stop()
	_flow = PackedFloat32Array()
	_intake_flow = PackedFloat32Array()
	_intake_read = 0
	_intake_q = 0.0
	_intake_lp = 0.0
	_intake_dc = 0.0
	exh.reset()
	_hist.fill(0.0)
	_delay.fill(0.0)
	_hp = 0
	_dp = 0
	_bucket = 0.0
	_bucket_n = 0
	_since = 0.0
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
	return flow * exh.air_factor(fresh)


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
