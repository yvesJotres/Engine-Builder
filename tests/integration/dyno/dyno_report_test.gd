extends SceneTree

# The correction factor, the cold-oil friction, and the sheet export. No full dyno pull.
# Run: godot --headless -s tests/integration/dyno/dyno_report_test.gd

var _fails := 0


func check(ok: bool, msg: String) -> void:
	print(("ok   " if ok else "FAIL ") + msg)
	if not ok:
		_fails += 1


func _init() -> void:
	var standard := DynoTest.sae_j1349_factor(99000.0, 298.15, 0.0)
	check(absf(standard - 1.0) < 0.01, "SAE J1349 is 1.0 on its own reference day (%.3f)" % standard)
	var here := DynoTest.sae_j1349_factor(101325.0, 300.0, 0.0)
	check(here > 0.95 and here < 1.0, "the sim's 300 K day corrects slightly under 1 (%.3f)" % here)
	var wet := DynoTest.sae_j1349_factor(101325.0, 300.0, 1.0)
	check(wet > here, "humid air raises the correction (%.3f vs %.3f)" % [wet, here])
	check(is_equal_approx(EngineSim.oil_friction_scale(100.0, 100.0), 1.0), "warm oil keeps the calibrated friction")
	check(EngineSim.oil_friction_scale(20.0, 100.0) > 1.5, "cold oil raises friction (%.2f)" % EngineSim.oil_friction_scale(20.0, 100.0))
	check(is_equal_approx(EngineSim.coolant_knock_penalty_deg(90.0), 0.0), "a 90 °C coolant does not tighten the knock margin")
	check(EngineSim.coolant_knock_penalty_deg(110.0) > 0.4, "a hot coolant tightens the knock margin")

	var spec := EngineSpec.new()
	spec.oil_temp_c = 20.0
	spec.coolant_temp_c = 20.0
	var sim := EngineSim.new()
	sim.physics_dt = 1.0 / 1200.0
	sim.omega = 3000.0 * TAU / 60.0
	sim.rpm = 3000.0
	sim.running = true
	for _i in 2400:
		sim.step(sim.physics_dt, spec, 0.4, true, false, false, false, 1.0)
	check(sim.oil_c > 22.0 and sim.oil_c < 100.0, "cold oil warms toward operating temperature (%.0f °C)" % sim.oil_c)
	check(sim.coolant_c > 22.0 and sim.coolant_c <= 90.0, "cold coolant warms toward operating temperature (%.0f °C)" % sim.coolant_c)

	var sheet := {
		"curve": [{"rpm": 3000.0, "torque": 10.0, "hp": 4.0, "corrected_torque": 9.8, "corrected_hp": 3.9, "bsfc_g_kwh": 280.0, "lambda": 0.9, "egt_c": 700.0, "intake_pa": 100000.0, "torque_stdev": 0.2, "samples": 40.0}],
		"gears": [{"gear": 1, "torque": 10.0, "torque_rpm": 3000.0, "hp": 4.0, "hp_rpm": 6000.0, "kmh": 40.0, "samples": 100.0}],
	}
	var csv := DynoTest.to_csv(sheet)
	check(csv.find("bsfc_g_kwh") != -1 and csv.find("40.0") != -1, "the csv carries the fuel consumption and the gear speed")
	var parsed = JSON.parse_string(DynoTest.to_json(sheet))
	check(parsed is Dictionary and float(parsed.curve[0].torque) == 10.0, "the json round-trips the curve")
	DynoTest.write_result(sheet, "user://dyno_report_test")
	check(FileAccess.file_exists("user://dyno_report_test.csv"), "write_result stores the csv")

	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
