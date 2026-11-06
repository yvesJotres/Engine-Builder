extends SceneTree

# Diagnostic: the TRX520 in the real scene at full throttle in neutral, rpm every 0.1 s. Print only.
func _init() -> void:
	await process_frame
	var index := 0
	for name in Presets.PRESETS:
		if name.begins_with("Honda TRX520"):
			break
		index += 1
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main._panel._on_preset_selected(index)
	await process_frame
	main._ignition = true
	main._touch_starter = true
	for i in 700:
		main._process(1.0 / 60.0)
	main._touch_starter = false
	for i in 900:
		main._process(1.0 / 60.0)
	print("idle %.0f rpm, redline %.0f" % [main._sim.rpm, main.spec.redline_rpm])
	main._touch_throttle = 1.0
	for i in 12:
		main._process(1.0 / 60.0)
		print("frame %2d: rpm %5.0f running %s trim %+.1f manifold %.1f kPa gas torque %+.1f knocks %d backfires %d throttle %.2f" % [i + 1, main._sim.rpm, str(main._sim.running), main._sim.ecu.trim, main._sim.intake.pressure / 1000.0, main._sim._gas_torque, main._sim.knock_count, main._sim.backfire_count, main._throttle])
	quit(0)
