extends SceneTree

# Writes short exhaust clips into this folder so they can be played in any audio app.
# Run: godot --headless -s res://sound/render_clips.gd
# Each file is mono 16-bit 44.1 kHz, scaled so the loudest point is 0.8.

const DT := 1.0 / 60.0
const RATE := 44100
const FRAME_SAMPLES := 735


func _init() -> void:
	await process_frame
	var dir := ProjectSettings.globalize_path("res://sound")
	DirAccess.make_dir_recursive_absolute(dir)
	var bike := EngineSpec.new()
	_save(dir, "crank", _run(bike, "crank"))
	_save(dir, "idle", _run(bike, "idle"))
	_save(dir, "rev", _run(bike, "rev"))
	for header in ["stock", "4-2-1"]:
		var four := EngineSpec.new()
		four.cylinders = 4
		four.displacement_cc = 600.0
		four.header = header
		_save(dir, "rev_%s" % header.replace("-", ""), _run(four, "rev"))
	quit()


func _save(dir: String, name: String, clip: Dictionary) -> void:
	var path := dir + "/%s.wav" % name
	_write_wav(path, clip["samples"])
	print("%s  %.1f s  peak %.3f before scaling  -> %s" % [name, clip["samples"].size() / float(RATE), clip["peak"], path])


# kind: crank (starter only), idle (catch, then sit), rev (catch, then open the throttle).
func _run(spec: EngineSpec, kind: String) -> Dictionary:
	var sim := EngineSim.new()
	sim.exhaust_solver = true
	var sound := EngineSound.new()
	root.add_child(sound)
	sound.setup(spec)
	var out := PackedFloat32Array()
	var gate := 0.0
	var throttle := 0.0
	var phase := "start"
	var t := 0.0
	var done := false
	while not done:
		var starter := phase == "start"
		var target := 0.0
		if phase == "start" and ((sim.rpm > 900.0 and t > 0.4) or t > 4.0):
			phase = "hold" if kind != "crank" else "done"
			t = 0.0
		elif phase == "hold" and t >= (1.2 if kind == "rev" else 4.0):
			phase = "open" if kind == "rev" else "done"
			t = 0.0
		elif phase == "open" and t >= 2.0:
			phase = "close"
			t = 0.0
		elif phase == "close" and t >= 1.2:
			phase = "done"
		elif phase == "done" and kind == "crank" and t >= 0.6:
			done = true
		elif phase == "done" and kind != "crank":
			done = true
		if phase == "open":
			target = 1.0
		throttle = move_toward(throttle, target, (1.5 if target > throttle else 3.0) * DT)
		if not done:
			sim.step(DT, spec, throttle, true, starter, true, false, 1.0)
			gate = move_toward(gate, 1.0 if sim.rpm > 1.0 else 0.0, DT / 0.05)
			sound.rpm = sim.rpm
			if sim.exhaust != null:
				sound.push_flow(sim.exhaust.take_flow())
			for frame in sound.render(FRAME_SAMPLES):
				out.append(frame.x * gate)
			t += DT
	sound.queue_free()
	var peak := 0.0
	for v in out:
		peak = maxf(peak, absf(v))
	return {"samples": out, "peak": peak}


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
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(header)
	file.store_buffer(data)
	file.close()
