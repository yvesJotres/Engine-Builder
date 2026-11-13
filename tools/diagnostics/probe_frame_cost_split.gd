extends SceneTree

# Diagnostic: split one frame's simulation cost into the parts that run per FRAME and the parts that run per physics
# sub-step. The rate sweep showed the cost is nearly flat from 1200 Hz to 200 Hz, which means the money is in the
# per-frame work, not in the integration.
# Run headless:  godot --headless --path . -s res://tools/diagnostics/probe_frame_cost_split.gd

const FRAMES := 300
const BIKES := ["yamaha_yzf_r1m", "bugatti_centodieci"]


func _init() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	for bike in BIKES:
		_split(main, bike)
	main.free()
	quit(0)


func _time(label: String, count: int, fn: Callable) -> float:
	var t0 := Time.get_ticks_usec()
	for i in count:
		fn.call()
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / float(count)
	print("    %-34s %6.3f ms  (%5.1f%% of the frame)" % [label, ms, ms / 16.667 * 100.0])
	return ms


func _split(main, bike: String) -> void:
	var index: int = main._panel._preset_ids.find(bike)
	if index < 0:
		return
	main._panel._on_preset_selected(index)
	main._panel.apply_to(main.spec)
	main.flush_rebuild()
	var spec = main.spec
	var sim: EngineSim = main._sim
	sim.physics_dt = 1.0 / 1200.0
	sim.running = true
	sim.gear.gear = 3
	sim.speed = 30.0
	var ratio: float = spec.primary_ratio * float(sim.gear.gear_ratios[2]) * spec.final_drive
	sim.omega = sim.speed / EngineSim.tire_radius_m(spec) * ratio
	sim.rpm = sim.omega * 60.0 / TAU
	for i in 60:
		sim.step(1.0 / 60.0, spec, 1.0, true, false, false, false, 1.0)

	print("\n%s (%d cylinders)" % [bike, spec.cylinders])
	var whole := _time("whole sim.step(1/60) at 1200 Hz", FRAMES,
		func() -> void: sim.step(1.0 / 60.0, spec, 1.0, true, false, false, false, 1.0))
	var build := _time("_build_cylinders (cache key + check)", FRAMES,
		func() -> void: sim._build_cylinders(spec))
	var dict := _time("_intake_spec_dict (30-field Dictionary)", FRAMES,
		func() -> void: sim._intake_spec_dict(spec))
	var setter := _time("intake.set_spec", FRAMES,
		func() -> void: sim.intake.set_spec(sim._intake_spec_dict(spec)))
	var ecu := _time("_sync_ecu_calibration", FRAMES,
		func() -> void: sim._sync_ecu_calibration(spec))
	print("    %-34s %6.3f ms  (unaccounted)" % ["rest of the frame", maxf(whole - build - dict - ecu, 0.0)])
