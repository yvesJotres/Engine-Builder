extends SceneTree

# Renders an idle sample for the default engine: 1 s start, then 5 s idle. Output: tools/diagnostics/samples/idle_cbr150.wav

# Output: tools/diagnostics/samples/idle_cbr150.wav
# Run: godot --headless -s tools/diagnostics/render_knock.gd

const DT := 1.0 / 60.0
const RATE := 44100
const FRAME_SAMPLES := 735

func _init() -> void:
	await process_frame
	var dir := ProjectSettings.globalize_path("res://tools/diagnostics/samples")
	DirAccess.make_dir_recursive_absolute(dir)
	var spec := EngineSpec.new()
	var sim := EngineSim.new()
	sim.exhaust_solver = true
	var sound := EngineSound.new()
	root.add_child(sound)
	sound.setup(spec)
	var out := PackedFloat32Array()
	var t := 0.0
	# seconds, throttle, timing offset, starter held
	var stages := [[1.0, 0.0, 0.0, true], [5.0, 0.0, 0.0, false]]
	for stage in stages:
		var seconds: float = stage[0]
		var throttle: float = stage[1]
		spec.ignition_offset_deg = stage[2]
		var end_t := t + seconds
		while t < end_t:
			sim.step(DT, spec, throttle, true, stage[3], false, false, 1.0)
			sound.rpm = sim.rpm
			if sim.exhaust != null:
				sound.push_flow(sim.exhaust.take_flow())
			for frame in sound.render(FRAME_SAMPLES):
				out.append(frame.x)
			t += DT
	sound.queue_free()
	var path := dir + "/idle_cbr150.wav"
	_write_wav(path, out)
	print("%.1f s, knock events %d, peak %.3f -> %s" % [out.size() / float(RATE), sim.knock_count, _peak(out), path])
	quit()

func _peak(s: PackedFloat32Array) -> float:
	var p := 0.0
	for v in s:
		p = maxf(p, absf(v))
	return p

func _write_wav(path: String, samples: PackedFloat32Array) -> void:
	var peak := maxf(_peak(samples), 0.0001)
	var gain := 0.8 / peak
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i] * gain, -1.0, 1.0) * 32767.0))
	var header := PackedByteArray()
	header.resize(44)
	header.encode_u32(0, 0x46464952)
	header.encode_u32(4, 36 + data.size())
	header.encode_u32(8, 0x45564157)
	header.encode_u32(12, 0x20746d66)
	header.encode_u32(16, 16)
	header.encode_u16(20, 1)
	header.encode_u16(22, 1)
	header.encode_u32(24, RATE)
	header.encode_u32(28, RATE * 2)
	header.encode_u16(32, 2)
	header.encode_u16(34, 16)
	header.encode_u32(36, 0x61746164)
	header.encode_u32(40, data.size())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(header)
	f.store_buffer(data)
	f.close()
