extends SceneTree

const WAV_WRITER := preload("res://scripts/audio/wav_writer.gd")
const FRAME_DT := 1.0 / 60.0
const SAMPLES_PER_FRAME := 735

func _init() -> void:
	await process_frame
	var directory := ProjectSettings.globalize_path("res://tools/diagnostics/samples")
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		push_error("Could not create diagnostics directory")
		quit(1)
		return
	var run_id := "%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var scenarios := [
		["cbr_idle", "Honda CBR150R (K45N)", 1200.0, 0.0],
		["cbr_high", "Honda CBR150R (K45N)", 9000.0, 1.0],
		["centodieci_idle", "Bugatti Centodieci (W16, approximate)", 1000.0, 0.0],
		["centodieci_high", "Bugatti Centodieci (W16, approximate)", 7000.0, 1.0],
	]
	for scenario in scenarios:
		var path := directory.path_join("%s_%s.wav" % [scenario[0], run_id])
		if not _record(scenario[1], scenario[2], scenario[3], path):
			quit(1)
			return
		print("RECORDING ", scenario[0], " ", path)
	quit()


func _record(preset_name: String, target_rpm: float, throttle: float, path: String) -> bool:
	var spec := EngineSpec.new()
	for key in Presets.PRESETS[preset_name]:
		spec.set(key, Presets.PRESETS[preset_name][key])
	var sim := EngineSim.new()
	sim.exhaust_solver = true
	sim.fuel.set_kind(spec.fuel)
	sim.running = true
	var sound := EngineSound.new()
	sound.setup(spec)
	var writer := WAV_WRITER.new()
	var error: String = writer.open(path, int(EngineSound.RATE), 1, 16)
	if error != "":
		push_error(error)
		sound.free()
		return false
	for frame in 300:
		sim.rpm = target_rpm
		sim.omega = target_rpm * TAU / 60.0
		sim.step(FRAME_DT, spec, throttle, true, false, true, false, 1.0)
		sound.rpm = target_rpm
		if sim.exhaust != null:
			sound.push_flow(sim.exhaust.take_flow())
		var output := sound.render(SAMPLES_PER_FRAME)
		if frame >= 180:
			writer.store_samples(output)
	writer.finish()
	sound.free()
	return true