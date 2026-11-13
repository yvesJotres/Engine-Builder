extends SceneTree

# Diagnostic: what the simulation costs per 60 Hz frame as the physics rate changes, with no rendering.
# Run headless:  godot --headless --path . -s res://tools/diagnostics/probe_frame_cost_rates.gd
# The pause menu's accuracy setting decides this rate; on a phone the question is what the device can still afford,
# and the cost is linear in the rate because each fixed step does the same work.

const FRAMES := 300
const RATES := [1200, 900, 600, 400, 300, 200]
const BIKES := ["yamaha_yzf_r1m", "bugatti_centodieci"]


func _init() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	for bike in BIKES:
		_sweep(main, bike)
	main.free()
	quit(0)


func _sweep(main, bike: String) -> void:
	var index: int = main._panel._preset_ids.find(bike)
	if index < 0:
		print("%s: preset not found" % bike)
		return
	main._panel._on_preset_selected(index)
	main._panel.apply_to(main.spec)
	main.flush_rebuild()
	var spec = main.spec
	var sim: EngineSim = main._sim
	print("\n%s (%d cylinders)" % [bike, spec.cylinders])
	for rate in RATES:
		sim.physics_dt = 1.0 / float(rate)
		sim.running = true
		sim.gear.gear = 3
		sim.speed = 30.0
		var ratio: float = spec.primary_ratio * float(sim.gear.gear_ratios[2]) * spec.final_drive
		sim.omega = sim.speed / EngineSim.tire_radius_m(spec) * ratio
		sim.rpm = sim.omega * 60.0 / TAU
		for i in 60:
			sim.step(1.0 / 60.0, spec, 1.0, true, false, false, false, 1.0)
		var t0 := Time.get_ticks_usec()
		for i in FRAMES:
			sim.step(1.0 / 60.0, spec, 1.0, true, false, false, false, 1.0)
		var per_frame := (Time.get_ticks_usec() - t0) / 1000.0 / float(FRAMES)
		print("  %4d Hz  %6.2f ms/frame   %5.0f%% of a 16.7 ms budget   %5.0f%% of a 33.3 ms budget"
			% [rate, per_frame, per_frame / 16.667 * 100.0, per_frame / 33.333 * 100.0])
	sim.physics_dt = 1.0 / 1200.0
