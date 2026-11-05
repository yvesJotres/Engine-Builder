extends SceneTree

# Asserting checks for the two sensors: the O2 sensor reads the mixture that is set (1.0 is exact, a rich or lean mixture
# reads what was asked), and the exhaust temperature sensor reads a plausible petrol exhaust temperature at full throttle.
# Run: godot --headless -s tests/sensors_test.gd (exit code 1 on failure)

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: " + msg)


func _run(lambda: float) -> EngineSim:
	var spec := EngineSpec.new()
	var sim := EngineSim.new()
	for i in 720: # crank and let it settle at idle
		sim.step(1.0 / 60.0, spec, 0.0, true, true, false, false, lambda)
	for i in 240:
		sim.step(1.0 / 60.0, spec, 0.0, true, false, false, false, lambda)
	return sim


func _init() -> void:
	await process_frame
	var stoich := _run(1.0)
	var lam := stoich.o2_lambda()
	print("O2 sensor at lambda 1.0: %.3f, exhaust %.0f C" % [lam, stoich.exhaust_temp_c()])
	check(absf(lam - 1.0) < 0.03, "the O2 sensor reads 1.0 at a stoichiometric mixture, got %.3f" % lam)

	var rich := _run(0.85)
	print("O2 sensor at lambda 0.85: %.3f" % rich.o2_lambda())
	check(absf(rich.o2_lambda() - 0.85) < 0.03, "the O2 sensor reads a rich mixture as set, got %.3f" % rich.o2_lambda())

	var lean := _run(1.15)
	print("O2 sensor at lambda 1.15: %.3f" % lean.o2_lambda())
	check(absf(lean.o2_lambda() - 1.15) < 0.03, "the O2 sensor reads a lean mixture as set, got %.3f" % lean.o2_lambda())

	# exhaust temperature at full throttle, a few thousand rpm: a petrol engine's exhaust is roughly 500 to 1000 C
	var spec := EngineSpec.new()
	var sim := EngineSim.new()
	for i in 720:
		sim.step(1.0 / 60.0, spec, 0.0, true, true, false, false, 1.0)
	for i in 600:
		sim.step(1.0 / 60.0, spec, 1.0, true, false, false, false, 1.0)
	var egt := sim.exhaust_temp_c()
	print("exhaust temperature at full throttle: %.0f C at %.0f rpm" % [egt, sim.rpm])
	check(egt > 400.0 and egt < 1100.0, "the exhaust temperature is plausible at full throttle, got %.0f C" % egt)

	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
