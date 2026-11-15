extends SceneTree

# Diagnostic: what one frame costs WHILE THE STARTER IS CRANKING, phase by phase, versus a frame of
# the same bike running. The phone drops to a few frames a second the moment the starter is held, so
# this splits the frame up and prints both cases side by side.
#
# Run headless:  godot --headless --path . -s res://tools/diagnostics/probe_crank_cost.gd

const FRAMES := 120
const BIKES := ["honda_cbr150r", "yamaha_yzf_r1m"]


func _init() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	for bike in BIKES:
		_measure(main, bike)
	main.free()
	quit(0)


func _time(label: String, count: int, fn: Callable) -> float:
	var t0 := Time.get_ticks_usec()
	for i in count:
		fn.call()
	return (Time.get_ticks_usec() - t0) / 1000.0 / float(count)


func _measure(main, bike: String) -> void:
	var index: int = main._panel._preset_ids.find(bike)
	if index < 0:
		return
	main._panel._on_preset_selected(index)
	main._panel.apply_to(main.spec)
	main.flush_rebuild()
	var spec = main.spec
	var sim: EngineSim = main._sim

	# 1. cranking: ignition on, starter held, no throttle, neutral. Same call main.gd makes.
	main._paused = false
	main._throttle = 0.0
	main._touch_starter = true
	main._touch_throttle = 0.0
	for i in 20:
		main._process(1.0 / 60.0)
	var crank_sim := _time("crank", FRAMES, func() -> void:
		sim.step(1.0 / 60.0, spec, 0.0, true, true, false, false, main._panel.lambda()))
	var crank_rest := _time("crank-rest", FRAMES, func() -> void: main._process(1.0 / 60.0))
	var rpm_cranking: float = sim.rpm
	main._touch_starter = false

	# 2. the same bike running at a road speed, for scale
	sim.running = true
	sim.gear.gear = 3
	sim.speed = 30.0
	var ratio: float = spec.primary_ratio * float(sim.gear.gear_ratios[2]) * spec.final_drive
	sim.omega = sim.speed / EngineSim.tire_radius_m(spec) * ratio
	sim.rpm = sim.omega * 60.0 / TAU
	main._throttle = 1.0
	for i in 20:
		main._process(1.0 / 60.0)
	var run_whole := _time("run", FRAMES, func() -> void: main._process(1.0 / 60.0))

	print("%-18s cranking: sim.step alone %6.3f ms   full _process %6.3f ms   (rpm %.0f)   running: %6.3f ms"
		% [bike, crank_sim, crank_rest, rpm_cranking, run_whole])
