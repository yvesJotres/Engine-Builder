extends SceneTree

# Compare the game's valve-flow source with its offline pipe solver at a fixed operating point.
# Run headless; the output is synthesized directly and does not measure the operating-system audio device.
const RATE := 44100
const BLOCK := 735
const FPS := 60.0
const WARMUP := 30
const CAPTURE := 120


func _init() -> void:
	await process_frame
	var dir := ProjectSettings.globalize_path("res://tools/diagnostics/out").path_join("sound_compare_%d" % Time.get_ticks_usec())
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		push_error("Cannot create output directory: " + dir)
		quit(1)
		return
	for id in ["honda_cbr150r", "honda_cbr250rr", "kawasaki_zx25r"]:
		for mode in ["baseline", "routed", "pipe"]:
			if not _capture(id, mode, dir):
				quit(1)
				return
	print("OUTPUT: ", dir)
	quit(0)


func _capture(id: String, mode: String, dir: String) -> bool:
	var spec := EngineSpec.new()
	var preset: Dictionary = Presets.PRESETS[id]
	for property in spec.get_property_list():
		var key: String = property.name
		if preset.has(key):
			spec.set(key, preset[key])
	var sim := EngineSim.new()
	sim.physics_dt = 1.0 / 2400.0
	sim.exhaust_solver = mode == "pipe"
	sim.fuel.set_kind(spec.fuel)
	var sound := EngineSound.new()
	var layout := ExhaustLayout.build(spec)
	if mode == "routed":
		sim.set_audio_layout(layout, spec.cylinders)
	sound.setup(spec, layout)
	var writer := WavWriter.new()
	var err := writer.open(dir.path_join(id + "_" + mode + ".wav"), RATE, 2, 16)
	if err != "":
		push_error(err)
		sound.free()
		return false
	var slow_frames := 0
	var deficit_frames := 0
	var deficit_samples := 0
	var max_ms := 0.0
	var sum_ms := 0.0
	for frame in WARMUP + CAPTURE:
		var start := Time.get_ticks_usec()
		sim.rpm = 6000.0
		sim.omega = 6000.0 * TAU / 60.0
		sim.running = true
		sim.step(1.0 / FPS, spec, 0.5, true, false, true, false, 1.0)
		var flow: PackedFloat32Array = sim.exhaust.take_flow() if mode == "pipe" else sim.take_blowdown()
		sound.push_flow(flow)
		sound.push_intake_flow(sim.take_intake_flow())
		sound.set_conditions(sim.o2_lambda(), sim.exhaust_temp_c(), sim.backpressure_pa())
		var available := sound._flow.size() - sound._read
		var frames := sound.render(BLOCK)
		var ms := (Time.get_ticks_usec() - start) / 1000.0
		if frame >= WARMUP:
			sum_ms += ms
			max_ms = maxf(max_ms, ms)
			if ms > 1000.0 / FPS:
				slow_frames += 1
			if available < BLOCK:
				deficit_frames += 1
				deficit_samples += BLOCK - available
			writer.store_samples(frames)
	writer.finish()
	sound.free()
	print("%s %s: avg %.2f ms, max %.2f ms, over 16.67 ms %d/%d, source shortages %d blocks / %d samples" % [id, mode, sum_ms / CAPTURE, max_ms, slow_frames, CAPTURE, deficit_frames, deficit_samples])
	return true
