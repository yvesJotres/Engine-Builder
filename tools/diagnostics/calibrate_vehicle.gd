extends SceneTree

# Calibrate (vehicle): tunes a bundled preset's mechanical values until its dyno run matches the online reference.
# Scored checks: peak power, peak power rpm, peak torque, and top speed in each gear the reference covers.
# Only tunable JSON values change. ECU binary, ve_scale and ignition offset are never touched. Physics changes are not
# automated here. The preset is rewritten only when every check passes, including the power curve. The old file goes to res://calibration/backups.
# Run: godot --headless --path . -s tools/diagnostics/calibrate_vehicle.gd -- honda_cbr250rr_sp_qs [max_runs] [error_pct]
# error_pct, when given, replaces the CALIBRATION_TOL limits for this bike only (for example 5 for 5%).

# Mechanical values the search may move, with physical bounds.
const TUNABLE := [
	{"section": "drivetrain", "key": "drag_area_m2", "lo": 0.25, "hi": 0.6},
	{"section": "geometry", "key": "vehicle_kg", "lo": 150.0, "hi": 180.0},
	{"section": "geometry", "key": "flywheel_kg", "lo": 2.5, "hi": 6.0},
	{"section": "drivetrain", "key": "clutch_capacity_nm", "lo": 15.0, "hi": 40.0},
	{"section": "valvetrain", "key": "intake_centre_deg", "lo": 455.0, "hi": 490.0},
	{"section": "valvetrain", "key": "intake_duration_deg", "lo": 235.0, "hi": 285.0},
	{"section": "valvetrain", "key": "exhaust_centre_deg", "lo": 245.0, "hi": 275.0},
	{"section": "valvetrain", "key": "exhaust_duration_deg", "lo": 225.0, "hi": 265.0},
]


var tol: Dictionary = OnlineDyno.CALIBRATION_TOL


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var preset_id := args[0] if args.size() > 0 else "honda_cbr250rr_sp_qs"
	var max_runs := int(args[1]) if args.size() > 1 else 24
	if args.size() > 2:
		var pct := float(args[2]) / 100.0
		tol = {"power": pct, "torque": pct, "peak_rpm": OnlineDyno.CALIBRATION_TOL.peak_rpm, "curve": pct, "top_speed": pct}
	var spec := DynoRunner.spec_for(preset_id)
	var reference := OnlineDyno.for_preset(preset_id)
	if spec == null or reference.is_empty():
		print("No preset or crank reference for %s" % preset_id)
		quit(2)
		return
	for p in TUNABLE:
		if not p.key in spec:
			print("Spec has no property %s" % p.key)
			quit(2)
			return

	var preset_path := "res://assets/engines/%s.json" % preset_id
	var preset_text := FileAccess.get_file_as_string(preset_path)
	var data: Dictionary = JSON.parse_string(preset_text)
	# A preset that leaves the clutch at 0 uses the derived capacity. Start the search from that value.
	if spec.clutch_capacity_nm <= 0.0:
		spec.clutch_capacity_nm = EngineSim.new().clutch_capacity(spec)

	print("=== Calibrate %s against %s ===" % [DynoRunner.display_name_for(preset_id), reference.get("title", "")])
	print("Scored: peak power, peak power rpm, peak torque, top speed in reference gears. Tolerances: %s" % str(tol))
	var best := _evaluate(spec, reference, preset_id)
	_print_run(0, "baseline", best)
	var runs := 1
	var step := 0.1
	while runs < max_runs and not best.criteria_ok and step >= 0.02:
		var improved := false
		for p in TUNABLE:
			if runs >= max_runs or best.criteria_ok:
				break
			var current: float = float(spec.get(p.key))
			for direction in [1.0, -1.0]:
				var trial := clampf(current + direction * step * (float(p.hi) - float(p.lo)), float(p.lo), float(p.hi))
				if is_equal_approx(trial, current):
					continue
				spec.set(p.key, trial)
				var candidate := _evaluate(spec, reference, preset_id)
				runs += 1
				_print_run(runs - 1, "%s = %.3f" % [p.key, trial], candidate)
				if candidate.score < best.score:
					best = candidate
					improved = true
					break
				spec.set(p.key, current)
				if runs >= max_runs:
					break
		if not improved:
			step *= 0.5

	print("")
	print("=== Verdict after %d runs ===" % runs)
	for line in best.summary:
		print(line)
	var report := DynoReport.build(best.result, DynoReport.conditions(spec, preset_id, DynoRunner.display_name_for(preset_id)), reference, tol)
	for path in DynoReport.write(report):
		print("report: " + path)

	if best.matched:
		var backup := "res://calibration/backups/%s_%s.json" % [preset_id, Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")]
		DirAccess.make_dir_recursive_absolute("res://calibration/backups")
		var backup_file := FileAccess.open(backup, FileAccess.WRITE)
		backup_file.store_string(preset_text)
		backup_file.close()
		for p in TUNABLE:
			data[p.section][p.key] = snappedf(float(spec.get(p.key)), 0.001)
		var out := FileAccess.open(preset_path, FileAccess.WRITE)
		out.store_string(JSON.stringify(data, "\t"))
		out.close()
		print("Preset written. Previous version kept at %s" % backup)
		quit(0)
	else:
		print("Preset not written: the match is not complete, so the bike stays as it was.")
		quit(1)


# Runs one dyno pull and scores it. Lower score is better.
func _evaluate(spec: EngineSpec, reference: Dictionary, preset_id: String) -> Dictionary:
	var result := DynoRunner.run(spec, preset_id)
	var summary := []
	var out := {"result": result, "score": 1.0e9, "criteria_ok": false, "matched": false, "summary": summary, "power": 0.0, "power_rpm": 0.0, "torque": 0.0, "top_kmh": 0.0}
	var cmp := OnlineDyno.compare(OnlineDyno.wheel_estimate(result.curve), reference, tol)
	if cmp.is_empty():
		summary.append("No dyno curve was produced.")
		return out
	var gears := OnlineDyno.compare_gears(result.gears, reference, tol)
	var power_rpm_error := float(cmp.power_rpm) - float(reference.peak_power_rpm)
	var torque_rpm_error := float(cmp.torque_rpm) - float(reference.peak_torque_rpm)
	var score: float = pow(float(cmp.power_error) / tol.power, 2) + pow(power_rpm_error / 200.0, 2) + pow(float(cmp.torque_error) / tol.torque, 2) + pow(torque_rpm_error / 500.0, 2)
	var speeds_ok := true
	for g in gears:
		score += pow(float(g.error) / tol.top_speed, 2)
		speeds_ok = speeds_ok and bool(g.pass)
		out.top_kmh = float(g.sim_kmh)
	var criteria := bool(cmp.power_pass) and bool(cmp.torque_pass) and bool(cmp.peak_rpm_pass) and speeds_ok
	out.score = score
	out.criteria_ok = criteria
	out.matched = criteria and bool(cmp.curve_pass)
	out.power = float(cmp.power_hp)
	out.power_rpm = float(cmp.power_rpm)
	out.torque = float(cmp.torque_nm)
	summary.append("Power %.2f hp (%+.1f%% vs %.1f): %s" % [cmp.power_hp, cmp.power_error * 100.0, reference.peak_power_hp, _pass(cmp.power_pass)])
	summary.append("Power rpm %d (%+d vs %d): %s" % [roundi(cmp.power_rpm), roundi(power_rpm_error), roundi(reference.peak_power_rpm), _pass(cmp.peak_rpm_pass)])
	summary.append("Torque %.2f N·m (%+.1f%% vs %.1f): %s" % [cmp.torque_nm, cmp.torque_error * 100.0, OnlineDyno.reference_peak_torque_nm(reference), _pass(cmp.torque_pass)])
	summary.append("Torque rpm %d (%+d vs %d): reported, not scored" % [roundi(cmp.torque_rpm), roundi(torque_rpm_error), roundi(reference.peak_torque_rpm)])
	for g in gears:
		summary.append("Gear %d top speed %.1f km/h (%+.1f%% vs %.1f): %s" % [g.gear, g.sim_kmh, g.error * 100.0, g.reference_kmh, _pass(g.pass)])
	if gears.is_empty():
		summary.append("Top speed: no reference")
	if cmp.curve_points_compared == 0:
		summary.append("Power curve: reference has no points, cannot be checked. Not matched.")
	else:
		summary.append("Power curve: %s" % _pass(cmp.curve_pass))
	summary.append("Score %.2f. Criteria met: %s. Matched: %s." % [score, str(criteria), str(out.matched)])
	return out


func _print_run(index: int, label: String, run: Dictionary) -> void:
	print("run %d [%s]: %.2f hp @ %d rpm, %.2f N·m, score %.2f, criteria %s" % [index, label, run.power, roundi(run.power_rpm), run.torque, run.score, str(run.criteria_ok)])


func _pass(ok: bool) -> String:
	return "pass" if ok else "FAIL"
