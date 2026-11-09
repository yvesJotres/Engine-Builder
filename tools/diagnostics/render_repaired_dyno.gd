extends SceneTree

func _init() -> void:
	var preset := "honda_cbr250rr"
	var hz := 2400.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--preset="):
			preset = arg.substr(9).validate_filename()
		elif arg.begins_with("--hz="):
			hz = maxf(float(arg.substr(5)), 2400.0)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child.call_deferred(main)
	await process_frame
	await process_frame
	main.set_process(false)
	var selected: int = main._panel._preset_ids.find(preset)
	assert(selected >= 0, "unknown preset")
	main._panel._on_preset_selected(selected)
	main._ignition = true
	main._sim.physics_dt = 1.0 / hz
	main._on_dyno_pressed()
	for i in 60 * 240:
		if not main._dyno.active():
			break
		main._process(1.0 / 60.0)
		if i % 120 == 0:
			await process_frame
	main._dyno_view.refresh(main._dyno)
	# This capture advances many simulation frames per rendered frame, so its FPS
	# overlay would describe the diagnostic batch rather than normal gameplay.
	for node in root.find_children("*", "CanvasLayer", true, false):
		if node.get_script() != null and str(node.get_script().resource_path).ends_with("fps_overlay.gd"):
			node.set_process(false)
			node.visible = false
	var result: Dictionary = main._dyno.result()
	result["physics_hz"] = hz
	result["wheel_estimate_efficiency"] = EngineSim.DRIVE_EFFICIENCY
	var wheel_rpm: float = main._sim.speed * main.spec.primary_ratio * main.spec.final_drive * main._sim.gear.ratio() / EngineSim.tire_radius_m(main.spec) * 60.0 / TAU
	result["terminal_slip_rpm"] = main._sim.rpm - wheel_rpm
	var online: Dictionary = preload("res://scripts/dyno/online_dyno.gd").for_preset(preset)
	if not online.is_empty():
		result["online_normalization"] = preload("res://scripts/dyno/online_dyno.gd").comparison_factor(online)
		result["online_comparison"] = preload("res://scripts/dyno/online_dyno.gd").compare(preload("res://scripts/dyno/online_dyno.gd").wheel_estimate(result.curve, result.online_normalization), online)
	print("Terminal engine %.1f RPM, road-coupled %.1f RPM, slip %.1f RPM; clutch capacity %.1f Nm" % [main._sim.rpm, wheel_rpm, result.terminal_slip_rpm, main.spec.clutch_capacity_nm])
	DynoTest.write_result(result, "res://build/dyno_%s_repaired" % preset)
	for i in 5:
		await process_frame
	var path := ProjectSettings.globalize_path("res://tools/diagnostics/out/dyno_%s_repaired.png" % preset)
	var error := root.get_texture().get_image().save_png(path)
	print("Screenshot %s: %d; completed=%s" % [path, error, result.ok])
	quit(error)
