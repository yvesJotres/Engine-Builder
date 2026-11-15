extends Node

# Diagnostic: what one frame of the running app costs on THIS device, split by phase.
#
# It borrows the live Main node from the scene tree, stops its own frame work, and then times
# each phase of main.gd's _process() by hand, so the numbers are the device's own CPU under the
# real scene, not a desktop reading. Run it on the phone from the launcher's menu (M), with the
# "Frame cost probe" button, or from a PC-like device with a hardware keyboard.
#
# Output: user://frame_phases.txt on the device (Settings > Apps > Engine Builder > Files, or
# `adb shell run-as com.enginebuilder.app cat files/frame_phases.txt` on a debug build), and the
# same lines in logcat under the "godot" tag.
#
# The phases mirror main.gd: sim, model, sound, hud, stats. If the total here is close to the
# frame time the phone reports, the CPU is the bottleneck; if it is small and the frame is still
# long, the time is in the renderer or the driver instead.

const ROUNDS := 240
const AUDIO_FRAMES := 735 # one 60 Hz frame of audio at 44.1 kHz
const WARMUP := 60


func _ready() -> void:
	await get_tree().process_frame
	# This node is added to the game's Main node, so the parent is the app whose frame we are timing.
	var main := get_parent()
	if main == null or not main.has_method("flush_rebuild"):
		_log("probe: add this under the game's Main node, not the root")
		return
	main.set_process(false)
	await get_tree().process_frame
	_measure_cranking(main)
	_measure(main)
	main.set_process(true)
	await get_tree().process_frame
	queue_free()


func _log(line: String) -> void:
	print(line)
	var path := ProjectSettings.globalize_path("user://frame_phases.txt")
	var f := FileAccess.open(path, FileAccess.WRITE if not _written else FileAccess.READ_WRITE)
	if f != null:
		if not _written:
			f.store_line("Engine Builder - frame phases on this device")
		f.seek_end()
		f.store_line(line)
		_written = true


var _written := false
var _acc := {}


func _time(label: String, fn: Callable) -> void:
	var t0 := Time.get_ticks_usec()
	fn.call()
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	_acc[label] = _acc.get(label, 0.0) + ms


# The frame while the starter is held: this is the case that stalls the phone, and it is not the
# same shape as a running frame (low rpm, no firing, the starter layer running).
func _measure_cranking(main) -> void:
	var spec = main.spec
	var sim: EngineSim = main._sim
	main._touch_starter = true
	main._throttle = 0.0
	for i in WARMUP:
		main._process(1.0 / 60.0)
	_acc.clear()
	var d := 1.0 / 60.0
	var t0 := Time.get_ticks_usec()
	for i in ROUNDS:
		_time("sim.step (cranking)", func() -> void:
			sim.step(d, spec, 0.0, true, true, false, false, main._panel.lambda()))
		_time("sound push (cranking)", func() -> void:
			main._sound.drive.update_from(sim, spec, 0.0)
			main._sound.set_conditions(sim.o2_lambda(), sim.exhaust_temp_c(), sim.backpressure_pa())
			main._sound.push_flow(sim.exhaust.take_flow() if sim.uses_pipe_sound() else sim.take_blowdown())
			main._sound.push_intake_flow(sim.take_intake_flow()))
	var total := (Time.get_ticks_usec() - t0) / 1000.0 / float(ROUNDS)
	for label in _acc:
		_log("  %-34s %6.3f ms" % [label, _acc[label] / float(ROUNDS)])
	_log("  %-34s %6.3f ms  (rpm %.0f)" % ["cranking pair", total, sim.rpm])
	var a0 := Time.get_ticks_usec()
	for i in 5:
		main._sound.render(AUDIO_FRAMES)
	_log("  %-34s %6.3f ms" % ["sound.render(735) in crank state", (Time.get_ticks_usec() - a0) / 1000.0 / 5.0])
	main._touch_starter = false


func _measure(main) -> void:
	var spec = main.spec
	var sim: EngineSim = main._sim
	# run the bike: a couple of gears up and moving, so every phase has real work to do
	sim.running = true
	sim.gear.gear = 3
	sim.speed = 30.0
	var ratio: float = spec.primary_ratio * float(sim.gear.gear_ratios[2]) * spec.final_drive
	sim.omega = sim.speed / EngineSim.tire_radius_m(spec) * ratio
	sim.rpm = sim.omega * 60.0 / TAU
	main._throttle = 1.0
	for i in WARMUP:
		main._process(1.0 / 60.0)
	_acc.clear()
	var t0 := Time.get_ticks_usec()
	for i in ROUNDS:
		_time("sim.step", func() -> void:
			sim.step(1.0 / 60.0, spec, main._throttle, main._ignition, false, main._digital_clutch, main._brake_held, main._panel.lambda()))
		_time("model (crank/throttle/combustion)", func() -> void:
			main._model.set_throttle(main._throttle)
			main._model.update_crank(main._crank)
			main._model.update_combustion(sim.cylinders, 1.0 / 60.0))
		_time("drivetrain + wheels", func() -> void: main._update_vehicle_wheels(1.0 / 60.0))
		_time("sound push (flow/conditions)", func() -> void:
			main._sound.rpm = sim.rpm
			main._sound.drive.update_from(sim, spec, main._throttle)
			main._sound.set_conditions(sim.o2_lambda(), sim.exhaust_temp_c(), sim.backpressure_pa())
			main._sound.push_flow(sim.exhaust.take_flow() if sim.uses_pipe_sound() else sim.take_blowdown())
			main._sound.push_intake_flow(sim.take_intake_flow()))
		_time("exhaust heat + plume", func() -> void:
			main._exhaust.update_heat(sim.exhaust_temp_c(), 1.0 / 60.0)
			main._backfire_flame.update(1.0 / 60.0)
			main._exhaust_fume.update(sim.exhaust_temp_c() + 273.15, sim.exhaust_mass_flow(), sim.o2_lambda(), 1.0 / 60.0))
		_time("stats text", func() -> void:
			main._stats.set_engine_data("RPM %.0f   torque %.1f   power %.1f" % [sim.rpm, sim.torque, Units.w_to_hp(Units.power_w(sim.torque, sim.rpm))])
			main._stats.set_sensors("Exhaust %.0f   O2 %.2f" % [sim.exhaust_temp_c(), sim.o2_lambda()]))
		_time("hud", func() -> void: main._hud.update(sim, spec, main._clutch_held, main._throttle, main._spl_db))
	var total := (Time.get_ticks_usec() - t0) / 1000.0 / float(ROUNDS)
	var bike := "?"
	if main._panel._preset_button.selected >= 0 and main._panel._preset_button.selected < main._panel._preset_ids.size():
		bike = str(main._panel._preset_ids[main._panel._preset_button.selected])
	_log("probe on %s, %.0f Hz physics, %d cylinders" % [OS.get_processor_name(), 1.0 / sim.physics_dt, spec.cylinders])
	# The two native classes the audio and the clock path use, and what a block of sound costs here.
	# Without the native convolver the fallback FIR runs 64 taps per sample in GDScript, which is the
	# difference between a phone holding 60 fps with sound and one sitting at 10.
	_log("  native clock: %s   native convolver: %s" % [
		ClassDB.class_exists("EngineSimClock"), ClassDB.class_exists("AudioConvolver")])
	var sound: Node = main._sound
	var t_block := Time.get_ticks_usec()
	for i in 5:
		sound.render(735) # one 60 Hz frame of audio at 44.1 kHz
	_log("  sound.render(735) x5                 %6.2f ms per block" % ((Time.get_ticks_usec() - t_block) / 1000.0 / 5.0))
	var quiet := PackedFloat32Array()
	quiet.resize(735)
	t_block = Time.get_ticks_usec()
	for i in 20:
		sound._convolve(quiet) # the native convolution on its own
	_log("  sound._convolve(735) x20             %6.2f ms per block (taps %d)" % [
		(Time.get_ticks_usec() - t_block) / 1000.0 / 20.0, sound._ir.size()])
	var p0 := Time.get_ticks_usec()
	for i in 10:
		sound._process(1.0 / 60.0) # the real per-frame audio call, including push_buffer into the generator
	_log("  EngineSound._process x10             %6.2f ms per call" % ((Time.get_ticks_usec() - p0) / 1000.0 / 10.0))
	t_block = Time.get_ticks_usec()
	for i in 5:
		sound.render(2048) # the audio block ceiling in engine_sound.gd
	_log("  sound.render(2048) x5                %6.2f ms per block" % ((Time.get_ticks_usec() - t_block) / 1000.0 / 5.0))
	var accounted := 0.0
	for label in _acc:
		var ms: float = _acc[label] / float(ROUNDS)
		accounted += ms
		_log("  %-34s %6.3f ms" % [label, ms])
	_log("  %-34s %6.3f ms" % ["measured total per frame", total])
	_log("  %-34s %6.3f ms" % ["unaccounted (sum vs total)", maxf(total - accounted, 0.0)])
	_log("  bike %s   %d fps measured by the engine" % [bike, Engine.get_frames_per_second()])
