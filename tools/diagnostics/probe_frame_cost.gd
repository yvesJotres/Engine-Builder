extends SceneTree

# Diagnostic: how much wall-clock time one 60 Hz frame of the simulation costs, with no rendering at all.
# Run headless:  godot --headless --path . -s res://tools/diagnostics/probe_frame_cost.gd
# This is the floor for any device: a phone's CPU is slower than this machine's, so whatever it prints here is the
# cheapest that frame can ever be before the GPU or the audio thread are asked for anything.

const FRAMES := 600
const BIKES := ["honda_cbr150r", "yamaha_yzf_r1m", "bugatti_centodieci"]


func _init() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	for bike in BIKES:
		_measure(main, bike)
	main.free()
	quit(0)


func _measure(main, bike: String) -> void:
	var index: int = main._panel._preset_ids.find(bike)
	if index < 0:
		print("%s: preset not found" % bike)
		return
	main._panel._on_preset_selected(index)
	main._panel.apply_to(main.spec)
	main.flush_rebuild()
	var spec = main.spec
	var sim: EngineSim = main._sim
	sim.running = true
	sim.gear.gear = 3
	sim.speed = 30.0
	var ratio: float = spec.primary_ratio * float(sim.gear.gear_ratios[2]) * spec.final_drive
	sim.omega = sim.speed / EngineSim.tire_radius_m(spec) * ratio
	sim.rpm = sim.omega * 60.0 / TAU
	# warm up so the first-frame allocations do not land in the measurement
	for i in 120:
		sim.step(1.0 / 60.0, spec, 1.0, true, false, false, false, 1.0)
	var t0 := Time.get_ticks_usec()
	for i in FRAMES:
		sim.step(1.0 / 60.0, spec, 1.0, true, false, false, false, 1.0)
	var total_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var per_frame := total_ms / float(FRAMES)
	var substeps := 1.0 / sim.physics_dt / 60.0
	print("%-22s %6.2f ms/frame at %.0f Hz  (%.1f substeps per 60 Hz frame)  = %.0f%% of a 16.7 ms budget"
		% [bike, per_frame, 1.0 / sim.physics_dt, substeps, per_frame / 16.667 * 100.0])
