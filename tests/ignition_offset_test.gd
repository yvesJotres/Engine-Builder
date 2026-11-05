extends SceneTree

# Checks the ignition offset: it moves the spark advance by exactly the offset, and the idle still holds with the ECU trim.
# Run: godot --headless -s tests/ignition_offset_test.gd (exit code 1 on failure)

const DT := 1.0 / 60.0
var _fails := 0


func check(ok: bool, msg: String) -> void:
	print(("ok   " if ok else "FAIL ") + msg)
	if not ok:
		_fails += 1


func _idle(offset: float) -> float:
	var spec := EngineSpec.new()
	spec.ignition_offset_deg = offset
	var sim := EngineSim.new()
	for i in 720:
		sim.step(DT, spec, 0.0, true, true, false, false, 1.0)
	for i in 1200:
		sim.step(DT, spec, 0.0, true, false, false, false, 1.0)
	return sim.rpm


func _init() -> void:
	await process_frame
	var base := EngineAir.spark_advance_deg(5000.0)
	check(absf(EngineAir.spark_advance_deg(5000.0, 5.0) - base - 5.0) < 1e-9, "+5 deg advances the spark by exactly 5 deg")
	check(absf(EngineAir.spark_advance_deg(5000.0, -3.0) - base + 3.0) < 1e-9, "-3 deg retards the spark by exactly 3 deg")
	var spec := EngineSpec.new()
	spec.ignition_offset_deg = 11.0
	check(spec.validation_warning() != "", "an offset of 11 deg fails validation")
	var idle_adv := _idle(2.0)
	var idle_ret := _idle(-4.0)
	check(idle_adv > 1100.0 and idle_adv < 1600.0, "idle holds with +2 deg advance (%.0f rpm)" % idle_adv)
	check(idle_ret > 1100.0 and idle_ret < 1600.0, "idle holds with -4 deg retard (%.0f rpm)" % idle_ret)
	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
