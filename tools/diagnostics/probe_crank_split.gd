extends SceneTree

# Diagnostic: prints main.gd's own per-frame split (SPLIT line) while the starter is held and again
# while the same bike is running, so the block responsible for a cranking slowdown shows up by name.
#
#   godot --headless --path . -s res://tools/diagnostics/probe_crank_split.gd [bike_id]

const BIKES := ["honda_cbr150r"]


func _init() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	var bike: String = BIKES[0]
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		bike = args[0]
	var index: int = main._panel._preset_ids.find(bike)
	if index < 0:
		print("preset not found: ", bike)
		quit(1)
		return
	main._panel._on_preset_selected(index)
	main._panel.apply_to(main.spec)
	main.flush_rebuild()
	main._paused = false
	main._split_on = true

	print("--- CRANKING (starter held, throttle shut) ---")
	main._touch_starter = true
	main._throttle = 0.0
	for i in 180:
		main._process(1.0 / 60.0)

	print("--- RUNNING (3rd gear, 30 m/s, wide open) ---")
	main._touch_starter = false
	var spec = main.spec
	var sim: EngineSim = main._sim
	sim.running = true
	sim.gear.gear = 3
	sim.speed = 30.0
	var ratio: float = spec.primary_ratio * float(sim.gear.gear_ratios[2]) * spec.final_drive
	sim.omega = sim.speed / EngineSim.tire_radius_m(spec) * ratio
	sim.rpm = sim.omega * 60.0 / TAU
	main._throttle = 1.0
	for i in 180:
		main._process(1.0 / 60.0)
	main.free()
	quit(0)
