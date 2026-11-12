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

	# Every format prints the clutch slip as a percentage, and DynoTest already stores slip_pct_peak as one
	# (slip / rpm * 100). A report that multiplied it again would print 5000% for a 50% slip.
	var report := {
		"created": "20260101-000000", "ok": true, "status": "done", "speed_kind": "road",
		"speed_end_reason": "limiter", "sae_factor": 1.0,
		"conditions": {"preset_id": "p", "display_name": "P", "stroke_type": "four_stroke", "displacement_cc": 1000.0,
			"redline_rpm": 14000.0, "idle_target_rpm": 1200.0, "fuel": "ron95", "header": "stock", "primary_ratio": 1.6,
			"final_drive": 2.5, "gear_ratios": [2.6], "wheel_radius_m": 0.3, "road_mass_kg": 200.0,
			"drag_area_m2": 0.35, "clutch_capacity_nm": 200.0, "ve_scale": 1.0, "ignition_offset_deg": 0.0, "ecu_binary": ""},
		"peak_torque": {"torque": 100.0, "rpm": 8000.0}, "peak_hp": {"hp": 150.0, "rpm": 12000.0},
		"gears": [{"gear": 1, "torque_nm": 90.0, "torque_rpm": 7000.0, "hp": 80.0, "hp_rpm": 9000.0, "top_kmh": 110.0,
			"top_kmh_rpm": 12000.0, "end_reason": "limiter", "slip_rpm_mean": 20.0, "slip_rpm_peak": 40.0,
			"slip_pct_peak": 50.0, "slip_samples": 10.0, "reference_kmh": 0.0, "top_speed_error": 0.0,
			"top_speed_status": "no reference"}],
		"online": {}, "reference": {},
	}
	check(DynoReport.to_csv(report).contains(",50.000,"), "the csv prints the 50% slip as 50, not 0.5 or 5000")
	check(DynoReport.to_markdown(report).contains("| 50.00 |"), "the markdown table prints the 50% slip as 50")
	check(DynoReport.to_text(report).contains("50.00"), "the text report prints the 50% slip as 50")

	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
