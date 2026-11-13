extends SceneTree

# Diagnostic: the same bike with and without its runner bore. A preset that sets runner_bore_mm gets a runner area above
# RUNNER_AREA, which switches the cylinder integration from STEP_DEG (10 deg) to LARGE_RUNNER_STEP_DEG (1 deg) - ten
# times the crank-angle work per revolution, and the physics-rate setting does not touch it.
# Run headless:  godot --headless --path . -s res://tools/diagnostics/probe_runner_step_cost.gd

const FRAMES := 300
const BIKES := ["yamaha_yzf_r1m", "honda_cbr1000rrr_sp", "kawasaki_h2r", "honda_cbr150r"]


func _init() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	for bike in BIKES:
		_measure(main, bike)
	main.free()
	quit(0)


func _run(sim, spec) -> float:
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
	return (Time.get_ticks_usec() - t0) / 1000.0 / float(FRAMES)


func _measure(main, bike: String) -> void:
	var index: int = main._panel._preset_ids.find(bike)
	if index < 0:
		print("%s: preset not found" % bike)
		return
	main._panel._on_preset_selected(index)
	main._panel.apply_to(main.spec)
	main.flush_rebuild()
	var spec = main.spec
	var kept_bore: float = spec.runner_bore_mm
	var as_shipped := _run(main._sim, spec)
	spec.runner_bore_mm = 0.0 # falls back to RUNNER_AREA, so STEP_DEG applies again
	var ten_deg := _run(main._sim, spec)
	spec.runner_bore_mm = kept_bore
	print("%-24s runner %.0f mm  %6.2f ms/frame   |  forced 29 mm  %6.2f ms/frame   x%.1f"
		% [bike, kept_bore, as_shipped, ten_deg, as_shipped / maxf(ten_deg, 0.001)])
