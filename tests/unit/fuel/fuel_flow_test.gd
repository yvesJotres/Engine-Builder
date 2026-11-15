extends SceneTree

# The fuel flow drives the exhaust loudness. Fuel is injected once per engine cycle, so a flow read from one physics step is
# zero most of the time and the sound drops out. This checks that the flow read once per frame is steady at idle.
# Run: godot --headless -s tests/unit/fuel/fuel_flow_test.gd (exit code 1 on failure)

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: " + msg)


func _init() -> void:
	await process_frame
	var spec := EngineSpec.new()
	var sim := EngineSim.new()
	for i in 360: # start it with the starter, then let it settle at idle
		sim.step(1.0 / 60.0, spec, 0.0, true, true, false, false, 1.0)
	for i in 240:
		sim.step(1.0 / 60.0, spec, 0.0, true, false, false, false, 1.0)
	check(sim.running, "the engine is running at idle")
	var zero_frames := 0
	var lo := 1.0e9
	var hi := 0.0
	var samples: Array[float] = []
	for i in 240: # four seconds, read once per frame as the game does
		sim.step(1.0 / 60.0, spec, 0.0, true, false, false, false, 1.0)
		samples.append(sim.fuel_flow)
		lo = minf(lo, sim.fuel_flow)
		hi = maxf(hi, sim.fuel_flow)
	var sorted := samples.duplicate()
	sorted.sort()
	var median: float = sorted[sorted.size() / 2]
	# The check is on a dropout, not on an absolute level: idle fuel flow is around 0.01 g/s, so a fixed floor
	# sits right on the operating point and flips on the mixture, not on a dropout. A frame at half the median
	# or below is what "the reading fell between injections" looks like.
	for value in samples:
		if value <= median * 0.5:
			zero_frames += 1
	print("fuel flow at idle: %.4f to %.4f g/s, median %.4f, %d of 240 frames below half the median" % [lo, hi, median, zero_frames])
	check(zero_frames == 0, "the fuel flow never drops out between injections, %d frames did" % zero_frames)
	check(hi < 3.0 * maxf(lo, 0.001), "the fuel flow is steady at idle (%.4f to %.4f g/s)" % [lo, hi])
	var cylinder := sim.cylinders[0]
	var peak_exhaust_flow := 0.0
	for angle in range(0, 720, 4):
		peak_exhaust_flow = maxf(peak_exhaust_flow, cylinder.exhaust_flow_at(angle))
	check(peak_exhaust_flow > 0.0, "cylinder records simulated exhaust flow")
	check(absf(cylinder.exhaust_flow_at(90.0)) < 0.000001, "closed exhaust valve records no flow")
	check(is_equal_approx(cylinder.exhaust_flow_at(200.0), cylinder.exhaust_flow_at(920.0)), "exhaust flow is periodic over the engine cycle")
	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
