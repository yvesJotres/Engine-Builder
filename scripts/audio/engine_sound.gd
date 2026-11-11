class_name EngineSound
extends AudioStreamPlayer3D

# Tail volume-flow from ExhaustGas is the source. Header length and backpressure are already in that flow.
# The exhaust pulse (edge, rasp, level) is made in ExhaustSound; this file convolves it with a per-engine exhaust body
# at the output rate: the recorded base is modified by the engine's own pipe geometry (ExhaustIr), or a measured
# per-bike IR replaces it through EngineSpec.exhaust_ir_path. The earlier version
# decimated the body to 16 kHz and kept only the first 8 ms (208 taps of a 219 ms recording): 10% of the IR's energy and
# nothing above 8 kHz. The convolution is native (AudioConvolver, 0.85% of one core at 1152 taps and /O2); the GDScript
# fallback uses a short kernel so the game still makes sound when the library is missing.
# Intake noise is mixed in at low level for realism at idle/part-throttle.

const RATE := 44100.0
const MAX_TAPS := 16384 # 372 ms at 44.1 kHz: longer than any bundled impulse response, so none is truncated
const FALLBACK_TAPS := 64 # GDScript FIR when the native library is missing: short, but audible
const WET := 0.84
const BACKFIRE_DURATION := 0.02
const IR_MUFFLER := "res://assets/ir/mild_exhaust.wav"
const IR_OPEN := "res://assets/ir/sharp_01.wav"
const INTAKE_MIX := 0.15 # intake noise level relative to exhaust
const INTAKE_HZ := 1400.0 # the intake honk, brighter than the muffled exhaust body

static var _kernels := {}
static var _generated_irs := {} # per-engine bodies built from the base IR + ExhaustIr

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
var _ir := PackedFloat32Array()
var _conv: Object = null # AudioConvolver, the native full-rate convolution; null falls back to the GDScript kernel
var _hist := PackedFloat32Array()
var _hp := 0
var _fire_frames := 0.0 # audio frames since the engine started firing
var _flow_scale := ExhaustSound.BASE_FLOW_SCALE
var _delay := PackedFloat32Array()
var _dp := 0
var compressor_load := 0.0
var _compressor_phase := 0.0
var _compressor_blades := 9.0
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
	_dp = 0
	_compressor_phase = 0.0
	starved = false
	exh.reset()
	_compressor_blades = maxf(_spec.compressor_blade_count, 1.0)
	_dc_a = ExhaustSound.alpha(ExhaustSound.DC_HZ)
	_intake_a = ExhaustSound.alpha(INTAKE_HZ)
	_layers = LayerBank.standard()
	_layers.configure(_spec)
	apply_levels(_spec) # the bank exists now, so the panel levels can scale it
	# The leveler sets the loudness. Volume flow already grows with displacement, and scaling by it
	# again pushed a large engine past the clipper, which turned the firing ripple into a buzz.
	_flow_scale = ExhaustSound.BASE_FLOW_SCALE
	_ir = _load_ir(_spec, layout)
	_conv = null
	if ClassDB.class_exists("AudioConvolver"):
		_conv = ClassDB.instantiate("AudioConvolver")
		_conv.set_ir(_ir)
	_hist = PackedFloat32Array()
	_hist.resize(_fallback_taps())
	_hp = 0
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
		drive.gear_whine = spec.sound_gear_whine
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
	# time since the engine started firing: the rpm-locked layers fade in over it, so a catch does not sweep like a spaceship
	_fire_frames = _fire_frames + frames if drive.running else 0.0
	drive.fire_time = _fire_frames / RATE
	var layer_mix := _layers.render(frames, drive)
	# The body runs at the output rate, so the impulse response is neither decimated nor folded down at 8 kHz.
	var body := PackedFloat32Array()
	body.resize(frames)
	var direct := PackedFloat32Array()
	direct.resize(frames)
	for i in frames:
		body[i] = exh.excite()
		var intake := _intake_sample()
		# Estimated electric compressor whine, following load rather than crank speed.
		var whine := 0.0
		if compressor_load > 0.0:
			# Electric compressor: use its shaft speed when the model has one; the load-based pitch is only a fallback.
			var speed := drive.compressor_speed_rpm
			var whine_hz := speed / 60.0 * _compressor_blades if speed > 1000.0 else 900.0 + 2600.0 * compressor_load
			whine_hz = clampf(whine_hz, 100.0, RATE * 0.45)
			_compressor_phase = fposmod(_compressor_phase + TAU * whine_hz / RATE, TAU)
			whine = sin(_compressor_phase) * compressor_load * 0.012
		direct[i] = intake + whine + layer_mix[i]
	var wet := _convolve(body)
	for i in frames:
		# Keep a small direct edge alongside the convolved body.
		var mix := wet[i] * WET + body[i] * (1.0 - WET) + body[i] * 0.40
		var sample := exh.shape(mix + direct[i], drive.running)
		_delay[_dp] = sample
		var side := _delay[(_dp + 18) % 32]
		_dp = (_dp + 1) % 32
		out[i] = Vector2(sample, sample * 0.7 + side * 0.3)
	if exh.starved:
		starved = true
		exh.starved = false
	return out


# Convolve the exhaust body with the impulse response. Native when the library is present.
func _convolve(body: PackedFloat32Array) -> PackedFloat32Array:
	if _conv != null:
		return _conv.process(body)
	var taps := _fallback_taps()
	if taps <= 0:
		return body
	var n := body.size()
	var wet := PackedFloat32Array()
	wet.resize(n)
	var ir := _ir
	for i in n:
		_hist[_hp] = body[i]
		var acc := 0.0
		var at := _hp
		for k in taps:
			acc += ir[k] * _hist[at]
			at -= 1
			if at < 0:
				at = taps - 1
		wet[i] = acc
		_hp += 1
		if _hp >= taps:
			_hp = 0
	return wet


func _fallback_taps() -> int:
	return mini(FALLBACK_TAPS, _ir.size())


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
	if _conv != null:
		_conv.reset()
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
	var flow := (_intake_lp - _intake_dc) * _flow_scale * INTAKE_MIX * _intake_scale
	return flow * exh.air_factor(fresh)


# Measured per-bike override wins. Otherwise the recorded base is modified by the engine's own pipe geometry,
# so every engine gets a distinct effective body instead of sharing one muffler can.
static func _load_ir(spec: EngineSpec, layout: ExhaustLayout) -> PackedFloat32Array:
	if spec.exhaust_ir_path != "":
		return _kernel(spec.exhaust_ir_path)
	var base_path := _base_ir_path(layout)
	var key := _ir_key(spec, layout, base_path)
	if _generated_irs.has(key):
		return _generated_irs[key]
	var base := _kernel(base_path)
	var body := ExhaustIr.modify(base, spec, layout)
	if body.is_empty():
		body = base
	_generated_irs[key] = body
	return body


static func _base_ir_path(layout: ExhaustLayout) -> String:
	if layout == null:
		return IR_MUFFLER
	for pipe in layout.pipes:
		if pipe.kind == "muffler":
			return IR_MUFFLER
	return IR_OPEN


static func _ir_key(spec: EngineSpec, layout: ExhaustLayout, base_path: String) -> String:
	var layout_key := ""
	if layout != null:
		for pipe in layout.pipes:
			layout_key += "%s:%.4f:%.6f;" % [pipe.kind, pipe.length_m(), pipe.area_m2()]
	return "%s|%d|%.2f|%.2f|%.2f|%s|%.2f|%s|%.1f|%s" % [
		base_path, spec.cylinders, spec.displacement_cc, spec.bore_mm, spec.stroke_mm, spec.header,
		spec.header_primary_mm, spec.muffler_style, spec.redline_rpm, layout_key,
	]


static func generated_ir_count() -> int:
	return _generated_irs.size()


static func clear_generated_irs() -> void:
	_generated_irs.clear()


static func _kernel(path: String) -> PackedFloat32Array:
	if _kernels.has(path):
		return _kernels[path]
	var pcm := _read_wav(path)
	var taps := MAX_TAPS
	if not pcm.is_empty():
		taps = mini(pcm.size(), MAX_TAPS)
	var kernel := PackedFloat32Array()
	kernel.resize(taps)
	if pcm.is_empty():
		for i in taps:
			var t := float(i) / RATE
			kernel[i] = exp(-t * 90.0) * sin(TAU * 240.0 * t)
	else:
		# the recording plays at the output rate: every sample is a tap, up to MAX_TAPS
		for i in taps:
			kernel[i] = pcm[i]
	var weight := 0.0
	for i in taps:
		weight += absf(kernel[i])
	if weight > 0.0:
		for i in taps:
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
		if value != 0:
			end = i + 1
	# keep the whole recording: the quiet tail is the sound of the canister and the room, and trimming it at an
	# absolute level (-50 dBFS here) was throwing away the part that gives the pipe its depth
	end = clampi(end, 0, mini(count, MAX_TAPS))
	if end == 0:
		return PackedFloat32Array()
	return samples.slice(0, end)
