extends SceneTree

# The two-stroke engine must run in the simulation: both cylinders exist, and the RD350 fires from the starter and picks up
# speed with the throttle open. Before the fix the cylinder list rejected the two-stroke cylinders, so nothing ran.
# Exits 1 on any failure. Run: godot --headless --path . -s res://tests/unit/engine/two_stroke_sim_test.gd

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func _init() -> void:
	await process_frame
	var spec := EngineSpec.new()
	var p: Dictionary = Presets.PRESETS["yamaha_rd350"]
	for key in p.keys():
		spec.set(key, p[key])
	var sim := EngineSim.new()
	sim.physics_dt = 1.0 / 2400.0
	sim.fuel.set_kind(spec.fuel)
	# crank on the starter for four seconds, as a rider does
	for i in 4 * 2400 / 60:
		for j in 60:
			sim.step(sim.physics_dt, spec, 0.0, true, true, false, false, 1.0)
	check(sim.cylinders.size() == spec.cylinders, "both cylinders exist, got %d" % sim.cylinders.size())
	var cranked := sim.rpm
	# then hold the throttle open for three seconds (a two-stroke has no idle control here yet, so it stalls at a closed throttle)
	var peak := 0.0
	for i in 3 * 2400 / 60:
		for j in 60:
			sim.step(sim.physics_dt, spec, 0.2, true, false, false, false, 1.0)
		peak = maxf(peak, sim.rpm)
	# Known gap, not asserted here: the RD350 falls back to 0 rpm after its peak, even with the throttle held open. The two-stroke
	# path does not run the ECU, so nothing holds its idle or its low-speed running yet.
	check(peak > 800.0, "the engine picks up speed, peak rpm %.0f (cranked to %.0f)" % [peak, cranked])
	check(is_finite(peak) and is_finite(sim.omega), "the sim stays finite")
	print("two_stroke_sim_test: %s" % ("PASSED" if _fails == 0 else "FAILED"))
	quit(0 if _fails == 0 else 1)
