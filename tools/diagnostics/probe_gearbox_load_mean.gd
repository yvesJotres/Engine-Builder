extends SceneTree

# Diagnostic: cycle-mean gearbox_load at WOT and with the throttle shut, frame by frame,
# for the bike the shift test uses. Read-only.

func _init() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main._panel._on_preset_selected(main._panel._preset_ids.find("yamaha_yzf_r1m"))
	main._panel.apply_to(main.spec)
	main.spec.quickshifter = false
	var spec = main.spec
	var sim: EngineSim = EngineSim.new()
	main._sim = sim
	sim.gear.gear_ratios = spec.gear_ratios
	sim.gear.gear = 3
	sim.speed = 12.0
	var ratio: float = spec.primary_ratio * float(sim.gear.gear_ratios[2]) * spec.final_drive
	sim.omega = sim.speed / EngineSim.tire_radius_m(spec) * ratio
	sim.rpm = sim.omega * 60.0 / TAU
	sim.running = true
	var threshold: float = maxf(0.5, sim.clutch_capacity(spec) * 0.08)
	print("capacity=", sim.clutch_capacity(spec), " threshold=", threshold)
	main._throttle = 1.0
	for frame in 60:
		sim.step(1.0 / 60.0, spec, main._throttle, true, false, false, false, 1.0)
	print("--- WOT ---")
	var wot_min := 1e9
	for frame in 40:
		sim.step(1.0 / 60.0, spec, 1.0, true, false, false, false, 1.0)
		wot_min = minf(wot_min, sim.gearbox_load)
		if frame < 10:
			print("wot f", frame, " mean=", sim.gearbox_load, " inst=", sim._gearbox_transfer, " unloaded=", absf(sim.gearbox_load) <= threshold)
	print("WOT mean min: ", wot_min)
	print("--- throttle shut ---")
	var shut_max := -1e9
	for frame in 42:
		sim.step(1.0 / 60.0, spec, 0.0, true, false, false, false, 1.0)
		shut_max = maxf(shut_max, absf(sim.gearbox_load))
		if frame < 10:
			print("shut f", frame, " mean=", sim.gearbox_load, " inst=", sim._gearbox_transfer, " unloaded=", absf(sim.gearbox_load) <= threshold)
	print("SHUT |mean| max: ", shut_max)
	main.free()
	quit(0)
