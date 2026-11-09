extends SceneTree

# Recreates the live sound path headless: the sim steps as in the game (60 frames a second, 2400 steps a second, no pipe
# solver), the flows are pushed as main.gd does, and EngineSound.render fills each frame. Writes six seconds at idle to a WAV.
# Run: godot --headless --path . -s tests/debug/live_idle_capture.gd -- <output_dir>
const SECONDS := 6.0
const RATE := 44100


func _init() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://"
	var mode := OS.get_cmdline_user_args()[1] if OS.get_cmdline_user_args().size() > 1 else "both"
	var spec := EngineSpec.new()
	var p: Dictionary = Presets.PRESETS["kawasaki_zx25r"]
	for key in p.keys():
		spec.set(key, p[key])
	var sim := EngineSim.new()
	sim.physics_dt = 1.0 / 2400.0 # the game's default steps per second
	sim.audio_enabled = true
	sim.fuel.set_kind(spec.fuel)
	var layout := ExhaustLayout.build(spec)
	var sound := EngineSound.new()
	sound.setup(spec, layout)
	sound.audio_enabled = true
	# warm up to idle, as a player would crank it
	var idle := spec.idle_target_rpm if spec.idle_target_rpm > 0 else 900.0
	var steps := 0
	while (not sim.running or sim.rpm < idle * 0.9) and steps < 40 * 2400:
		sim.step(sim.physics_dt, spec, 0.0, true, true, false, false, 1.0)
		sim.take_blowdown()
		sim.take_intake_flow()
		steps += 1
	var path := out.path_join("live_idle_%s.wav" % mode)
	var writer := WavWriter.new()
	writer.open(path, RATE, 2, 16)
	writer.write_header()
	var frames_per_video := int(RATE / 60.0)
	var video_frames := int(SECONDS * 60.0)
	for f in video_frames:
		for i in 2400 / 60:
			sim.step(sim.physics_dt, spec, 0.0, true, false, false, false, 1.0)
		sound.rpm = sim.rpm
		sound.set_conditions(sim.o2_lambda(), sim.exhaust_temp_c(), sim.backpressure_pa())
		var exhaust_flow = sim.take_blowdown()
		var intake_flow = sim.take_intake_flow()
		sound.push_flow(exhaust_flow if mode != "intake" else PackedFloat32Array())
		sound.push_intake_flow(intake_flow if mode != "exhaust" else PackedFloat32Array())
		writer.store_samples(sound.render(frames_per_video))
	writer.finish()
	print("LIVE rpm at end %.0f, wrote %s" % [sim.rpm, path])
	quit()
