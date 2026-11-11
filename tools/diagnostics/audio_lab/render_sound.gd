extends SceneTree
# Renders an engine's sound to a WAV for analysis. Driven by audio_lab.py; can also be run directly:
#   godot --headless --path . -s res://tools/diagnostics/audio_lab/render_sound.gd -- preset=yamaha_yzf_r1m seconds=6 out=C:/path/x.wav
# Options (key=value after --):
#   preset=<id>             preset id (assets/engines/<id>.json), default yamaha_yzf_r1m
#   seconds=<s>             length, default 6
#   profile=idle|decel|crank|crank_dry|rev  idle: closed throttle. decel: 0.8 throttle for 2.5 s, then closed. crank_dry: cranking with no spark. rev: wide open in neutral, from idle up to the limiter.
#                           crank: starts from rest with the starter held, records the cranking itself
#   solver=live|offline     live (default, what the game uses for four-strokes): blowdown pulses.
#                           offline: the 1D pipe solver (the offline render path)
#   intake=on|off           off: intake flow zeroed
#   exhaust=on|off          off: exhaust pulses zeroed
#   rasp=on|off             off: rasp noise removed
#   muffler=on|off          off: muffler impulse response bypassed
#   layers=on|off           off: the sound layers (valve tick, bottom end, driveline, turbo, knock) removed
#   gains=a,b,c,d,e         layer gains in bank order: valvetrain, mechanical, driveline, turbo, knock (desktop set)
#   raw=<path>              also dump the raw exhaust pulses as float32 (live solver only)
#   out=<path>              WAV path (required)

const WAV := preload("res://scripts/audio/wav_writer.gd")

func _args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		var parts := a.split("=", true, 1)
		if parts.size() == 2:
			out[parts[0]] = parts[1]
	return out

func _init() -> void:
	await process_frame
	var o := _args()
	var preset_id: String = o.get("preset", "yamaha_yzf_r1m")
	var seconds := float(o.get("seconds", "6"))
	var profile: String = o.get("profile", "idle")
	var offline: bool = o.get("solver", "live") == "offline"
	var intake_on: bool = o.get("intake", "on") != "off"
	var exhaust_on: bool = o.get("exhaust", "on") != "off"
	var rasp_on: bool = o.get("rasp", "on") != "off"
	var muffler_on: bool = o.get("muffler", "on") != "off"
	var layers_on: bool = o.get("layers", "on") != "off"
	var out_path: String = o.get("out", "")
	var raw_path: String = o.get("raw", "")
	if out_path == "" or not Presets.PRESETS.has(preset_id):
		print("LAB_ERROR need out=<path> and a valid preset=<id>")
		quit(1)
		return

	var spec := EngineSpec.new()
	var preset: Dictionary = Presets.PRESETS[preset_id]
	for key in preset.keys():
		spec.set(key, preset[key])
	var layout := ExhaustLayout.build(spec)
	var sim := EngineSim.new()
	sim.exhaust_solver = offline
	sim.physics_dt = 1.0 / 28800.0
	sim.fuel.set_kind(spec.fuel)
	var sound := EngineSound.new()
	sound.setup(spec, layout)
	sound.rpm = spec.idle_target_rpm
	if not muffler_on:
		sound._ir = PackedFloat32Array([1.0])
	sound._layers.enabled = layers_on
	var gain_list: String = o.get("gains", "")
	if gain_list != "":
		var parts := gain_list.split(",")
		for i in parts.size():
			sound._layers.set_gain(i, float(parts[i]))

	var writer := WAV.new()
	writer.open(out_path, 44100, 2, 16)
	writer.write_header()
	var raw_file: FileAccess = null
	if raw_path != "" and not offline:
		raw_file = FileAccess.open(raw_path, FileAccess.WRITE)

	# warm up at idle, the same way the game does before recording (a cranking recording starts from rest instead)
	var steps := 0
	if not profile.begins_with("crank"):
		# hold the starter until the engine is well up, as a player does: releasing it near the firing speed can drop a big engine
		while (not sim.running or sim.rpm < spec.idle_target_rpm * 1.5) and steps < int(40.0 / sim.physics_dt):
			sim.step(sim.physics_dt, spec, 0.0, true, true, false, false, 1.0)
			steps += 1
		for i in int(1.0 / sim.physics_dt):
			sim.step(sim.physics_dt, spec, 0.0, true, false, false, false, 1.0)
	_take_exhaust(sim, offline)
	sim.take_intake_flow()

	var total := int(seconds * 44100)
	var written := 0
	var per_step := 44100.0 * sim.physics_dt
	var remainder := 0.0
	var clock := 0.0
	while written < total:
		var throttle := 0.0
		if profile == "decel" and clock < 2.5:
			throttle = 0.8
		elif profile == "rev":
			throttle = 1.0
		# crank_dry: the starter turns the engine but the spark stays off, so it cranks without firing
		sim.step(sim.physics_dt, spec, throttle, profile != "crank_dry", profile.begins_with("crank"), false, false, 1.0)
		clock += sim.physics_dt
		sound.rpm = sim.rpm
		sound.drive.update_from(sim, spec, throttle)
		sound.set_conditions(sim.o2_lambda(), sim.exhaust_temp_c(), sim.backpressure_pa())
		if not rasp_on:
			sound.exh.noise_mix = 0.0
		var exhaust_flow: PackedFloat32Array = _take_exhaust(sim, offline)
		if not exhaust_on:
			exhaust_flow.fill(0.0)
		if raw_file != null:
			raw_file.store_buffer(exhaust_flow.to_byte_array())
		sound.push_flow(exhaust_flow)
		var intake_flow: PackedFloat32Array = sim.take_intake_flow()
		if not intake_on:
			intake_flow.fill(0.0)
		sound.push_intake_flow(intake_flow)
		remainder += per_step
		var frames := int(remainder)
		remainder -= frames
		frames = mini(frames, total - written)
		writer.store_samples(sound.render(frames))
		written += frames
		if written % (44100 * 4) < frames:
			await process_frame
	if raw_file != null:
		raw_file.close()
	writer.finish()
	sound.free()
	print("LAB_DONE ", out_path, " rpm=", snappedf(sim.rpm, 1))
	quit()

# the exhaust samples for the chosen solver: blowdown pulses live, the pipe solver's flow offline
func _take_exhaust(sim: EngineSim, offline: bool) -> PackedFloat32Array:
	if offline:
		return sim.exhaust.take_flow() if sim.exhaust != null else PackedFloat32Array()
	return sim.take_blowdown()
