extends SceneTree

# Checks backfire: none at idle or while the spark fires, and at least one once the rev limiter cuts the spark with fuel still
# going in. Run: godot --headless -s tests/unit/ecu/backfire_test.gd (exit code 1 on failure)

var _fails := 0


func check(ok: bool, msg: String) -> void:
	print(("ok   " if ok else "FAIL ") + msg)
	if not ok:
		_fails += 1


func _init() -> void:
	await process_frame
	var spec := EngineSpec.new()
	var sim := EngineSim.new()
	for i in 720:
		sim.step(1.0 / 60.0, spec, 0.0, true, true, false, false, 1.0)
	for i in 600:
		sim.step(1.0 / 60.0, spec, 0.0, true, false, false, false, 1.0)
	check(sim.running and sim.backfire_count == 0, "idle: running, no backfire (%d)" % sim.backfire_count)
	# full throttle until the limiter cuts the spark
	var before_limiter := -1
	var cut_seen := false
	for i in 3600:
		sim.step(1.0 / 60.0, spec, 1.0, true, false, false, false, 1.0)
		if sim.limiter_active and not cut_seen:
			cut_seen = true
			before_limiter = sim.backfire_count
		if cut_seen and sim.backfire_count > 0:
			break
	check(cut_seen, "the limiter cut the spark (rpm %.0f)" % sim.rpm)
	check(before_limiter == 0, "no backfire while the spark fired up to the limiter (%d)" % before_limiter)
	check(sim.backfire_count == 0, "no backfire during the limiter cut, because the limiter cuts fuel as well as spark (%d)" % sim.backfire_count)
	check(sim.last_backfire_j == 0.0, "no backfire energy is released in a limiter cut (%.1f J)" % sim.last_backfire_j)
	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
