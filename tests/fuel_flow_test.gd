extends SceneTree

# The fuel flow drives the exhaust loudness. Fuel is injected once per engine cycle, so a flow read from one physics step is
# zero most of the time and the sound drops out. This checks that the flow read once per frame is steady at idle.
# Run: godot --headless -s tests/fuel_flow_test.gd (exit code 1 on failure)

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
	for i in 240: # four seconds, read once per frame as the game does
		sim.step(1.0 / 60.0, spec, 0.0, true, false, false, false, 1.0)
		if sim.fuel_flow < 0.01:
			zero_frames += 1
		lo = minf(lo, sim.fuel_flow)
		hi = maxf(hi, sim.fuel_flow)
	print("fuel flow at idle: %.3f to %.3f g/s, %d of 240 frames near zero" % [lo, hi, zero_frames])
	check(zero_frames == 0, "the fuel flow never drops to zero between injections, %d frames did" % zero_frames)
	check(hi < 3.0 * maxf(lo, 0.001), "the fuel flow is steady at idle (%.3f to %.3f g/s)" % [lo, hi])
	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
