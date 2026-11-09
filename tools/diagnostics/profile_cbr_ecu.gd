extends SceneTree

# CPU-only comparison of the CBR250RR high-RPM simulation with its N04 maps
# enabled and disabled. Run headlessly so rendering and audio do not mask the
# ECU cost.
const SAMPLES := 120
const RPM := 13000.0


func _init() -> void:
	await process_frame
	var main: Variant = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	var preset_index: int = main._panel._preset_ids.find("honda_cbr250rr")
	if preset_index < 0:
		push_error("CBR250RR preset unavailable")
		quit(1)
		return
	main._panel._on_preset_selected(preset_index)
	main._on_sound_toggled(false)
	var bin_path: String = main.spec.ecu_binary
	var enabled := _measure(main)
	main.spec.ecu_binary = ""
	var disabled := _measure(main)
	main.spec.ecu_binary = bin_path
	print("CBR_ECU_PROFILE rpm=%.0f samples=%d ECU_on=%.3fms ECU_off=%.3fms overhead=%.1f%%" % [RPM, SAMPLES, enabled, disabled, (enabled / maxf(disabled, 0.001) - 1.0) * 100.0])
	main.free()
	quit()


func _measure(main: Variant) -> float:
	var sim: EngineSim = main._sim
	var start := Time.get_ticks_usec()
	for _i in SAMPLES:
		sim.rpm = RPM
		sim.omega = RPM * TAU / 60.0
		sim.running = true
		sim.step(1.0 / 60.0, main.spec, 0.7, true, false, false, false, 1.0)
	return float(Time.get_ticks_usec() - start) / SAMPLES / 1000.0
