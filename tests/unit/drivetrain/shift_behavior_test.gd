extends SceneTree

var _fails := 0

func _init() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	# The app opens on whatever engine was last used, so choose the bike whose ratios the checks below work in and
	# take the spec from the panel, as the game does.
	main._panel._on_preset_selected(main._panel._preset_ids.find("yamaha_yzf_r1m"))
	main._panel.apply_to(main.spec)
	# The checks below are about an ordinary clutch shift, so the bike's quickshifter is off. It stays fitted:
	# on a bike without one, a clutch-less upshift needs the throttle closed, which is a different test.
	main.spec.quickshifter = false
	var sim: EngineSim = main._sim
	sim.gear.gear_ratios = main.spec.gear_ratios
	sim.gear.gear = 2
	sim.speed = 12.0
	sim.clutch_engage = 1.0
	sim.gear.gear_ratios = main.spec.gear_ratios
	# the engine has to be turning at the gear's own speed, or the shift is refused as a rev mismatch before the load is looked at
	var settled_ratio: float = main.spec.primary_ratio * float(sim.gear.gear_ratios[1]) * main.spec.final_drive
	sim.rpm = sim.speed / EngineSim.tire_radius_m(main.spec) * settled_ratio * 60.0 / TAU
	sim.gearbox_load = 10.0
	main._throttle = 1.0
	main._shift(true)
	check(sim.gear.gear == 2 and main._pending_shift == 1, "loaded upshift remains preloaded")
	main._throttle = 0.0
	main._update_shift_request(0.1)
	# The pedal needs the throttle shut, which is the shift itself: the stated load is kept for the next block.
	check(sim.gear.gear == 3 and main._pending_shift == 0, "closing the throttle on a preloaded upshift completes it")
	sim.gearbox_load = 10.0
	main._throttle = 1.0
	main._shift(true)
	main._update_shift_request(1.0)
	check(sim.gear.gear == 3 and main._pending_shift == 0, "loaded shift expires without changing gear")
	sim.clutch_engage = 0.0
	main._shift(false)
	check(sim.gear.gear == 2, "open clutch permits a downshift")
	sim.clutch_engage = 1.0
	sim.gearbox_load = 0.0
	sim.rpm = 1000.0
	main._shift(false)
	check(sim.gear.gear == 0 and main._pending_shift == -1, "unloaded clutchless downshift waits in neutral for rev matching")
	var target_ratio: float = main.spec.primary_ratio * float(sim.gear.gear_ratios[0]) * main.spec.final_drive
	sim.rpm = sim.speed / EngineSim.tire_radius_m() * target_ratio * 60.0 / TAU
	main._update_shift_request(0.1)
	check(sim.gear.gear == 1, "rev-matched clutchless downshift engages first while moving")
	sim.clutch_engage = 0.0
	main._shift(true)
	check(sim.gear.gear == 2, "moving upshift goes directly from first to second")
	sim = EngineSim.new()
	main._sim = sim
	sim.gear.gear_ratios = main.spec.gear_ratios
	sim.gear.gear = 3
	sim.speed = 12.0
	var ratio: float = main.spec.primary_ratio * float(sim.gear.gear_ratios[2]) * main.spec.final_drive
	sim.omega = sim.speed / EngineSim.tire_radius_m() * ratio
	sim.rpm = sim.omega * 60.0 / TAU
	sim.running = true
	main._throttle = 1.0
	for frame in 60:
		sim.step(1.0 / 60.0, main.spec, main._throttle, true, false, false, false, 1.0)
	main._shift(true)
	for frame in 6:
		sim.step(1.0 / 60.0, main.spec, main._throttle, true, false, false, false, 1.0)
		main._update_shift_request(1.0 / 60.0)
	check(sim.gear.gear == 3, "full-throttle preload does not force the shift")
	main._throttle = 0.0
	for frame in 40:
		sim.step(1.0 / 60.0, main.spec, main._throttle, true, false, false, false, 1.0)
		main._update_shift_request(1.0 / 60.0)
	check(sim.gear.gear == 4, "throttle lift unloads the simulated gearbox and completes the upshift")
	main._throttle = 1.0
	for frame in 60:
		sim.step(1.0 / 60.0, main.spec, main._throttle, true, false, false, false, 1.0)
	# The engine has to be turning at this gear's own speed, or the downshift is held back for a rev match
	# before the load is ever looked at, and the check below would pass for the wrong reason.
	var held_ratio: float = main.spec.primary_ratio * float(sim.gear.gear_ratios[sim.gear.gear - 1]) * main.spec.final_drive
	sim.rpm = sim.speed / EngineSim.tire_radius_m(main.spec) * held_ratio * 60.0 / TAU
	main._shift(false)
	for frame in 6:
		sim.step(1.0 / 60.0, main.spec, main._throttle, true, false, false, false, 1.0)
		main._update_shift_request(1.0 / 60.0)
	check(sim.gear.gear == 4, "loaded downshift stays in gear")
	var saw_neutral := false
	for frame in 42:
		if sim.gear.gear == 0:
			saw_neutral = true
			main._throttle = 1.0
		else:
			main._throttle = 0.0
		sim.step(1.0 / 60.0, main.spec, main._throttle, true, false, false, false, 1.0)
		main._update_shift_request(1.0 / 60.0)
		if sim.gear.gear == 3:
			break
	check(saw_neutral and sim.gear.gear == 3, "unloaded downshift engages after a simulated throttle blip")
	main.spec.transmission_type = "dual_clutch"
	main.spec.gear_ratios = [3.2, 2.1, 1.5, 1.15, 0.92, 0.75, 0.63]
	sim.gear.gear = 6
	sim.gearbox_load = 100.0
	main._throttle = 1.0
	main._shift(true)
	check(sim.gear.gear == 7, "dual-clutch paddle upshift can select seventh under load")
	sim.gear.gear = 2
	sim.speed = 100.0
	main._shift(false)
	check(sim.gear.gear == 2, "dual-clutch downshift protects against overrevving")
	main.free()
	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)

func check(ok: bool, message: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + message)