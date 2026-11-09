class_name AudioRenderer
extends Node

# Renders the engine exhaust sound to a WAV file offline, at the highest simulation
# refresh (physics_dt = 1/3600). Runs the sim and the sound engine in a tight loop,
# yielding each chunk so the UI stays responsive.
#
# Usage:
#   var ar := AudioRenderer.new()
#   add_child(ar)
#   ar.render_completed.connect(func(path): print("Rendered: " + path))
#   ar.render(spec, layout, duration=10.0, sample_rate=44100, bit_depth=16, throttle=1.0)

signal render_completed(path: String)
signal render_failed(message: String)
signal render_progress(progress: float) # 0.0 to 1.0

const DEFAULT_DURATION := 10.0 # seconds
const DEFAULT_SAMPLE_RATE := 44100 # Hz
const DEFAULT_BIT_DEPTH := 16 # bits per sample
const DEFAULT_THROTTLE := 1.0 # 0..1, wide open
const WAV_WRITER_SCRIPT := preload("res://scripts/audio/wav_writer.gd")

# Renders `duration` seconds of exhaust audio to a WAV file.
# Runs at physics_dt = 1/3600 (highest accuracy), ignoring MAX_FRAME_TIME caps.
func render(spec: EngineSpec, layout: ExhaustLayout = null,
			duration: float = DEFAULT_DURATION,
			sample_rate: int = DEFAULT_SAMPLE_RATE,
			bit_depth: int = DEFAULT_BIT_DEPTH,
			throttle: float = DEFAULT_THROTTLE,
			output_directory: String = "") -> void:

	if sample_rate != int(EngineSound.RATE):
		render_failed.emit("Audio rendering currently supports 44,100 Hz only.")
		return
	if duration <= 0.0:
		render_failed.emit("Render duration must be positive.")
		return
	if layout == null:
		layout = ExhaustLayout.build(spec)

	# Output path in the user data folder
	var dir := ProjectSettings.globalize_path("user://renders") if output_directory == "" else output_directory
	var dir_access := DirAccess.open(dir)
	if dir_access == null or not dir_access.dir_exists(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var timestamp := Time.get_datetime_string_from_system()
	timestamp = timestamp.replace(" ", "_").replace(":", "-")
	var path := dir.path_join("engine_render_%s.wav" % [timestamp])

	var sim := EngineSim.new()
	sim.exhaust_solver = true # the pipe solver is for this offline render, not the live frame
	sim.physics_dt = 1.0 / 3600.0 # highest refresh: one step per 1/3600 s
	sim.fuel.set_kind(spec.fuel)

	# Sound engine mirrors the live one's configuration
	var sound := EngineSound.new()
	sound.setup(spec, layout)
	sound.rpm = spec.idle_target_rpm if spec.idle_target_rpm > 0 else 900.0

	var writer := WAV_WRITER_SCRIPT.new()
	var err := writer.open(path, sample_rate, 2, bit_depth)
	if err != "":
		sound.free()
		render_failed.emit(err)
		return
	writer.write_header()

	var total_samples := int(duration * sample_rate)
	var samples_written := 0
	var samples_per_physics_step := sample_rate * sim.physics_dt
	var sample_remainder := 0.0

	# Prime the sim: run a few steps at idle so the engine is running before we render
	# Crank until the engine runs at idle (a fixed 2 s was not enough: the engine stalled once the throttle opened).
	# Capped at 40 s of simulated time so a dead engine cannot hang the render.
	var idle_rpm := spec.idle_target_rpm if spec.idle_target_rpm > 0 else 900.0
	var warmup_steps := 0
	while (not sim.running or sim.rpm < idle_rpm * 0.9) and warmup_steps < int(40.0 / sim.physics_dt):
		sim.step(sim.physics_dt, spec, 0.0, true, true, false, false, 1.0)
		warmup_steps += 1
	# Let the engine settle at idle before recording
	for i in int(1.0 / sim.physics_dt):
		sim.step(sim.physics_dt, spec, 0.0, true, false, false, false, 1.0)
	if sim.exhaust != null:
		sim.exhaust.take_flow()
	sim.take_intake_flow()

	var render_start := Time.get_ticks_msec()
	var backfires_heard := sim.backfire_count

	while samples_written < total_samples:
		# Step the physics forward by one physics_dt
		sim.step(sim.physics_dt, spec, throttle, true, false, false, false, 1.0)

		# Drive the sound from the sim's current state
		sound.rpm = sim.rpm
		sound.set_conditions(sim.o2_lambda(), sim.exhaust_temp_c(), sim.backpressure_pa())
		if sim.exhaust != null:
			sound.push_flow(sim.exhaust.take_flow())
		sound.push_intake_flow(sim.take_intake_flow())

		if sim.backfire_count != backfires_heard:
			backfires_heard = sim.backfire_count

		# Render audio for this physics step. The gas solver already sampled the tail at the output rate.
		sample_remainder += samples_per_physics_step
		var frames_for_step := int(sample_remainder)
		sample_remainder -= frames_for_step
		var frames_remaining := total_samples - samples_written
		if frames_for_step > frames_remaining:
			frames_for_step = frames_remaining

		var frames := sound.render(frames_for_step)
		writer.store_samples(frames)
		samples_written += frames_for_step

		# Report progress and yield so the UI stays responsive
		var progress := float(samples_written) / float(total_samples)
		if samples_written % (sample_rate * 4) < frames_for_step: # roughly every 4 seconds of audio
			render_progress.emit(progress)
			await get_tree().process_frame

	writer.finish()
	sound.free()

	var elapsed := (Time.get_ticks_msec() - render_start) / 1000.0
	print("Rendered %d seconds of audio to %s in %.2f s" % [duration, path, elapsed])
	render_completed.emit(path)
