extends SceneTree

# Render Dyno — runs the full dyno test at high physics resolution and exports the engine sound to a WAV file.
# Run: godot --headless -s tools/diagnostics/render_dyno.gd --preset "honda_cbr150r" --physics_dt 1/7200 --output "user://dyno_render.wav"
#
# Arguments:
#   --preset "Name"           Engine preset to use (default: first preset)
#   --physics_dt 1/7200       Physics step size (default: 1/7200 for high quality)
#   --output "user://file.wav" Output WAV path (default: user://dyno_render_<preset>.wav)
#   --sample_rate 44100       Audio sample rate (default: 44100)
#   --normalize 0.8           Normalize peak to this level 0-1 (default: 0.8)

const DEFAULT_PHYSICS_DT := 1.0 / 7200.0
const DEFAULT_SAMPLE_RATE := 44100
const DEFAULT_NORMALIZE := 0.8
const FRAME_DT := 1.0 / 60.0 # frame rate for throttle/clutch updates
const FRAME_SAMPLES := int(DEFAULT_SAMPLE_RATE / 60.0) # samples per frame at 44.1k/60fps

var _preset_name := ""
var _render_all := false
var _physics_dt := DEFAULT_PHYSICS_DT
var _output_path := ""
var _sample_rate := DEFAULT_SAMPLE_RATE
var _normalize := DEFAULT_NORMALIZE

func _init() -> void:
	_parse_args()
	await process_frame # autoloads and class names ready
	
	var preset_dict := Presets.PRESETS
	
	# Batch mode: render all presets if --all is specified
	if _render_all:
		print("Batch mode: rendering all %d presets" % preset_dict.size())
		for name in preset_dict.keys():
			_render_single(name, preset_dict[name])
		quit(0)
	
	if _preset_name == "":
		_preset_name = preset_dict.keys()[0]
	
	if not preset_dict.has(_preset_name):
		print("Preset not found: %s. Available: %s" % [_preset_name, preset_dict.keys()])
		quit(1)
	
	_render_single(_preset_name, preset_dict[_preset_name])
	quit(0)

func _render_single(preset_name: String, p: Dictionary) -> void:
	var output_path := _output_path
	if output_path == "":
		var clean := _file_name(preset_name)
		output_path = "user://dyno_render_%s.wav" % clean
	
	output_path = ProjectSettings.globalize_path(output_path)
	var dir := output_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	
	print("\nRendering dyno for: %s" % preset_name)
	print("  physics_dt: %s (%.0f Hz)" % [_physics_dt, 1.0 / _physics_dt])
	print("  sample_rate: %d Hz" % _sample_rate)
	print("  output: %s" % output_path)
	
	var spec := EngineSpec.new()
	for key in p.keys():
		spec.set(key, p[key])
	
	var samples := _render_dyno(spec, preset_name, output_path)
	
	if samples.is_empty():
		print("  Skipped (dyno failed)")
		return
	
	_write_wav(output_path, samples)
	
	var duration := samples.size() / float(_sample_rate)
	print("Done: %.1f s (%d samples) -> %s" % [duration, samples.size(), output_path])

func _parse_args() -> void:
	var args = OS.get_cmdline_args()
	for i in range(args.size()):
		match args[i]:
			"--preset":
				if i + 1 < args.size():
					_preset_name = args[i + 1]
			"--all":
				_render_all = true
			"--physics_dt":
				if i + 1 < args.size():
					var val: String = args[i + 1]
					if val.contains("/"):
						var parts := val.split("/")
						_physics_dt = float(parts[0]) / float(parts[1])
					else:
						_physics_dt = float(val)
			"--output":
				if i + 1 < args.size():
					_output_path = args[i + 1]
			"--sample_rate":
				if i + 1 < args.size():
					_sample_rate = int(args[i + 1])
			"--normalize":
				if i + 1 < args.size():
					_normalize = float(args[i + 1])

func _render_dyno(spec: EngineSpec, preset_name: String, output_path: String) -> PackedFloat32Array:
	var sim := EngineSim.new()
	sim.exhaust_solver = true
	sim.physics_dt = _physics_dt
	
	var sound := EngineSound.new()
	root.add_child(sound) # _ready loads IR
	sound.setup(spec)
	
	var dyno := DynoTest.new()
	dyno.start(spec, sim)
	
	var out := PackedFloat32Array()
	var gate := 0.0
	var frame_count := 0
	var done := false
	var last_status := ""
	
	while not done:
		# Advance dyno by one frame (1/60s)
		dyno.advance(FRAME_DT, sim, spec, 1.0, true)
		frame_count += 1
		
		if not dyno.active():
			done = true
		
		# Progress log every 5 seconds of sim time
		var sim_time := frame_count * FRAME_DT
		if int(sim_time) % 5 == 0 and dyno.status != last_status:
			print("  [%6.1f s sim] %s  (rpm %.0f, gear %d)" % [sim_time, dyno.status, sim.rpm, sim.gear.gear])
			last_status = dyno.status
		
		# Update sound inputs for this frame
		gate = move_toward(gate, 1.0 if sim.running else 0.0, FRAME_DT / 0.05)
		sound.rpm = sim.rpm
		if sim.exhaust != null:
			sound.push_flow(sim.exhaust.take_flow())
		
		# Render audio for this frame
		var frame_samples := int(_sample_rate * FRAME_DT)
		for frame in sound.render(frame_samples):
			out.append(frame.x * gate)
	
	# Check if dyno completed successfully
	var r := dyno.result()
	if not dyno.ok:
		print("  DYNO FAILED: %s" % dyno.status)
		sound.queue_free()
		return PackedFloat32Array() # empty array
	
	# Export dyno curve as JSON alongside WAV
	var curve_data := {
		"preset": preset_name,
		"physics_dt": _physics_dt,
		"sample_rate": _sample_rate,
		"sim_time": frame_count * FRAME_DT,
		"peak_torque": r.peak_torque,
		"peak_hp": r.peak_hp,
		"gears": r.gears,
		"curve": r.curve
	}
	var json_path := output_path.replace(".wav", "_curve.json")
	var file := FileAccess.open(json_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(curve_data, "	"))
	file.close()
	print("  Curve data: %s" % json_path)
	
	sound.queue_free()
	return out

# Writes mono 16-bit PCM, scaled so the loudest sample is _normalize of full scale.
func _write_wav(path: String, samples: PackedFloat32Array) -> void:
	var peak := 0.0001
	for v in samples:
		peak = maxf(peak, absf(v))
	var gain := _normalize / peak
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i] * gain, -1.0, 1.0) * 32767.0))
	var header := PackedByteArray()
	header.resize(44)
	header.encode_u32(0, 0x46464952) # "RIFF"
	header.encode_u32(4, 36 + data.size())
	header.encode_u32(8, 0x45564157) # "WAVE"
	header.encode_u32(12, 0x20746d66) # "fmt "
	header.encode_u32(16, 16)
	header.encode_u16(20, 1) # PCM
	header.encode_u16(22, 1) # mono
	header.encode_u32(24, _sample_rate)
	header.encode_u32(28, _sample_rate * 2)
	header.encode_u16(32, 2)
	header.encode_u16(34, 16)
	header.encode_u32(36, 0x61746164) # "data"
	header.encode_u32(40, data.size())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(header)
	file.store_buffer(data)
	file.close()

func _file_name(preset_name: String) -> String:
	var clean := ""
	for c in preset_name.to_lower():
		clean += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") else "_"
	while clean.contains("__"):
		clean = clean.replace("__", "_")
	return clean.trim_suffix("_")