extends SceneTree

# Renders a sound sample for every engine preset, the way the game plays it: ignition on, a start with the starter, a 4 second
# idle, then rev bombing (short and long throttle blips up to the limiter). Each sample is a mono 16-bit 44.1 kHz WAV in
# tools/diagnostics/samples/, scaled so its loudest point is 0.8 (so quiet and loud engines can both be heard).
# Run: godot --headless -s tools/diagnostics/render_samples.gd

const DT := 1.0 / 60.0
const RATE := 44100
const FRAME_SAMPLES := 735 # RATE / 60
const BLIPS := [[0.4, 0.45], [0.4, 0.45], [0.4, 0.45], [0.8, 0.5], [0.8, 0.5]] # [throttle open seconds, closed seconds]


func _init() -> void:
	await process_frame # autoloads and class names are ready after the first frame
	var dir := ProjectSettings.globalize_path("res://tools/diagnostics/samples")
	DirAccess.make_dir_recursive_absolute(dir)
	for preset_name in Presets.PRESETS.keys():
		var p: Dictionary = Presets.PRESETS[preset_name]
		var spec := EngineSpec.new()
		for key in p.keys():
			spec.set(key, p[key])
		var samples := _render(spec)
		var path := dir + "/" + _file_name(preset_name) + ".wav"
		_write_wav(path, samples)
		print("%-30s %5.1f s  -> %s" % [preset_name, samples.size() / float(RATE), path])
	quit()


func _render(spec: EngineSpec) -> PackedFloat32Array:
	var sim := EngineSim.new()
	var sound := EngineSound.new()
	root.add_child(sound) # its _ready loads the exhaust impulse response
	sound.setup(spec)
	var max_air := Units.AIR_DENSITY * spec.displacement_cc * 1.0e-6 * (spec.redline_rpm / 120.0)
	var max_fuel := max_air / float(FuelTank.PROPERTIES[sim.fuel.kind].afr) * 1000.0
	var out := PackedFloat32Array()
	var gate := 0.0
	var throttle := 0.0
	var state := "off"
	var t := 0.0 # seconds in the current state
	var blip := 0
	var opening := true
	var done := false
	while not done:
		# the player's inputs for this frame
		var ignition := state != "off" or t > 0.3
		var starter := state == "start"
		var target_throttle := 0.0
		match state:
			"off":
				if t >= 0.6:
					state = "start"
					t = 0.0
			"start":
				# hold the starter until the engine is above 900 rpm, then a little longer, as a rider would
				if sim.rpm > 900.0 and t > 0.3 or t > 8.0:
					state = "idle"
					t = 0.0
			"idle":
				if t >= 4.0:
					state = "bomb"
					t = 0.0
					blip = 0
					opening = true
			"bomb":
				var blip_open: float = BLIPS[blip][0]
				var blip_closed: float = BLIPS[blip][1]
				target_throttle = 1.0 if opening else 0.0
				if opening and t >= blip_open:
					opening = false
					t = 0.0
				elif not opening and t >= blip_closed:
					blip += 1
					opening = true
					t = 0.0
					if blip >= BLIPS.size():
						state = "tail"
						t = 0.0
			"tail":
				if t >= 1.5:
					done = true
		# the throttle opens at 1.5 per second and springs shut at 3 per second, as in the game
		throttle = move_toward(throttle, target_throttle, (1.5 if target_throttle > throttle else 3.0) * DT)
		sim.step(DT, spec, throttle, ignition, starter, false, false, 1.0)
		# the sound inputs, as main.gd sets them each frame
		gate = move_toward(gate, 1.0 if sim.running else 0.0, DT / 0.05)
		sound.rpm = sim.rpm
		sound.firing = sim.running and not sim.limiter_active
		sound.energy = sqrt(clampf(sim.fuel_flow / max_fuel, 0.0, 1.0))
		for frame in sound.render(FRAME_SAMPLES):
			out.append(frame.x * gate)
		t += DT
	sound.queue_free()
	return out


# Writes mono 16-bit PCM, scaled so the loudest sample is 0.8 of full scale.
func _write_wav(path: String, samples: PackedFloat32Array) -> void:
	var peak := 0.0001
	for v in samples:
		peak = maxf(peak, absf(v))
	var gain := 0.8 / peak
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
	header.encode_u32(24, RATE)
	header.encode_u32(28, RATE * 2)
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
