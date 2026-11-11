class_name DynoReport
extends RefCounted

# The printed dyno report: per-gear peaks, top speed, clutch slip and the conditions an online comparison needs.
# It reads a finished DynoTest.result() and never changes the run it describes.

const DIR := "user://dyno_reports"


# The settings a reader needs to judge a run: ratios, mass, drag, clutch, ECU and the simulator's own limits.
static func conditions(spec: EngineSpec, preset_id: String, display_name: String) -> Dictionary:
	return {
		"preset_id": preset_id,
		"display_name": display_name,
		"stroke_type": spec.stroke_type,
		"displacement_cc": spec.displacement_cc,
		"redline_rpm": spec.redline_rpm,
		"idle_target_rpm": spec.idle_target_rpm,
		"fuel": spec.fuel,
		"header": spec.header,
		"primary_ratio": spec.primary_ratio,
		"final_drive": spec.final_drive,
		"gear_ratios": spec.gear_ratios,
		"wheel_radius_m": EngineSim.tire_radius_m(spec),
		"road_mass_kg": spec.road_mass_kg(),
		"drag_area_m2": spec.drag_area_m2,
		"clutch_capacity_nm": spec.clutch_capacity_nm,
		"ve_scale": spec.ve_scale,
		"ignition_offset_deg": spec.ignition_offset_deg,
		"ecu_binary": spec.ecu_binary,
	}


# Builds the report. reference is an OnlineDyno crank reference, or {} when none exists. tol sets the top-speed tolerance.
static func build(result: Dictionary, conditions_data: Dictionary, reference: Dictionary, tol: Dictionary) -> Dictionary:
	var ref_speeds: Dictionary = reference.get("per_gear_top_speed_kmh", {})
	var rows := []
	for g in result.get("gears", []):
		var key := str(g.gear)
		var ref_kmh := float(ref_speeds[key].kmh) if ref_speeds.has(key) else 0.0
		var status := "no reference"
		var error := 0.0
		if ref_kmh > 0.0:
			if float(g.kmh) <= 0.0:
				status = "not reached"
			else:
				error = float(g.kmh) / ref_kmh - 1.0
				status = "matched" if absf(error) <= float(tol.top_speed) else "outside tolerance"
		rows.append({
			"gear": int(g.gear), "torque_nm": float(g.torque), "torque_rpm": float(g.torque_rpm),
			"hp": float(g.hp), "hp_rpm": float(g.hp_rpm),
			"top_kmh": float(g.kmh), "top_kmh_rpm": float(g.get("top_kmh_rpm", 0.0)), "end_reason": str(g.get("end_reason", "")),
			"slip_rpm_mean": float(g.get("slip_rpm_mean", 0.0)), "slip_rpm_peak": float(g.get("slip_rpm_peak", 0.0)),
			"slip_pct_peak": float(g.get("slip_pct_peak", 0.0)), "slip_samples": float(g.get("slip_samples", 0.0)),
			"reference_kmh": ref_kmh, "top_speed_error": error, "top_speed_status": status,
		})
	return {
		"created": _stamp(),
		"ok": result.get("ok", false),
		"status": str(result.get("status", "")),
		"speed_kind": str(result.get("speed_kind", "road")),
		"speed_end_reason": str(result.get("speed_end_reason", "")),
		"sae_factor": float(result.get("sae_factor", 1.0)),
		"conditions": conditions_data,
		"peak_torque": result.get("peak_torque", {}),
		"peak_hp": result.get("peak_hp", {}),
		"gears": rows,
		"online": {} if reference.is_empty() else OnlineDyno.compare(OnlineDyno.wheel_estimate(result.get("curve", [])), reference, tol),
		"reference": {} if reference.is_empty() else {
			"title": str(reference.get("title", "")), "basis": str(reference.get("basis", "")),
			"source_url": str(reference.get("source_url", "")),
			"peak_power_hp": float(reference.peak_power_hp), "peak_power_rpm": float(reference.peak_power_rpm),
			"peak_torque_nm": OnlineDyno.reference_peak_torque_nm(reference), "peak_torque_rpm": float(reference.get("peak_torque_rpm", 0.0)),
		},
	}


static func to_text(report: Dictionary) -> String:
	var c: Dictionary = report.conditions
	var lines := PackedStringArray()
	lines.append("DYNO REPORT  %s  (%s)" % [c.display_name, c.preset_id])
	lines.append("Created %s   Run status: %s" % [report.created, report.status])
	lines.append("Crankshaft output, cycle-averaged. Speed kind: %s, end: %s. SAE J1349 factor %.4f." % [report.speed_kind, report.speed_end_reason, report.sae_factor])
	lines.append("")
	lines.append("Peak torque  %.2f N·m at %d rpm" % [report.peak_torque.get("torque", 0.0), roundi(report.peak_torque.get("rpm", 0.0))])
	lines.append("Peak power   %.2f hp at %d rpm" % [report.peak_hp.get("hp", 0.0), roundi(report.peak_hp.get("rpm", 0.0))])
	lines.append("")
	lines.append("Gear  N·m    rpm    hp     rpm    km/h   rpm    slip mean  slip peak  slip %  end        ref km/h  speed check")
	for r in report.gears:
		var ref_text := "%.1f" % r.reference_kmh if r.reference_kmh > 0.0 else "-"
		lines.append("%-5d %-6.2f %-6d %-6.2f %-6d %-6.1f %-6d %-10.1f %-10.1f %-7.2f %-10s %-9s %s" % [
			r.gear, r.torque_nm, roundi(r.torque_rpm), r.hp, roundi(r.hp_rpm), r.top_kmh, roundi(r.top_kmh_rpm),
			r.slip_rpm_mean, r.slip_rpm_peak, r.slip_pct_peak, r.end_reason, ref_text, r.top_speed_status])
	lines.append("")
	if report.reference.is_empty():
		lines.append("Reference: none for this preset.")
	else:
		var ref: Dictionary = report.reference
		lines.append("Reference: %s (%s)" % [ref.title, ref.basis])
		lines.append("  Peak power %.1f hp at %d rpm, peak torque %.1f N·m at %d rpm" % [ref.peak_power_hp, roundi(ref.peak_power_rpm), ref.peak_torque_nm, roundi(ref.peak_torque_rpm)])
		for line in _online_lines(report):
			lines.append(line)
	lines.append("")
	lines.append("Conditions")
	for key in ["stroke_type", "displacement_cc", "redline_rpm", "idle_target_rpm", "fuel", "header", "primary_ratio", "final_drive",
			"wheel_radius_m", "road_mass_kg", "drag_area_m2", "clutch_capacity_nm", "ve_scale", "ignition_offset_deg", "ecu_binary"]:
		lines.append("  %s: %s" % [key, str(c[key])])
	lines.append("  gear_ratios: %s" % str(c.gear_ratios))
	return "\n".join(lines) + "\n"


static func to_markdown(report: Dictionary) -> String:
	var c: Dictionary = report.conditions
	var lines := PackedStringArray()
	lines.append("# Dyno report: %s" % c.display_name)
	lines.append("")
	lines.append("- Preset: `%s`, created %s" % [c.preset_id, report.created])
	lines.append("- Run status: %s (speed %s, end %s), SAE J1349 factor %.4f" % [report.status, report.speed_kind, report.speed_end_reason, report.sae_factor])
	lines.append("- Peak torque %.2f N·m at %d rpm; peak power %.2f hp at %d rpm (crankshaft)" % [
		report.peak_torque.get("torque", 0.0), roundi(report.peak_torque.get("rpm", 0.0)), report.peak_hp.get("hp", 0.0), roundi(report.peak_hp.get("rpm", 0.0))])
	lines.append("")
	lines.append("| Gear | N·m | rpm | hp | rpm | Top km/h | rpm at top | Slip mean rpm | Slip peak rpm | Slip peak % | End | Ref km/h | Speed check |")
	lines.append("|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---:|---|")
	for r in report.gears:
		var ref_text := "%.1f" % r.reference_kmh if r.reference_kmh > 0.0 else "-"
		lines.append("| %d | %.2f | %d | %.2f | %d | %.1f | %d | %.1f | %.1f | %.2f | %s | %s | %s |" % [
			r.gear, r.torque_nm, roundi(r.torque_rpm), r.hp, roundi(r.hp_rpm), r.top_kmh, roundi(r.top_kmh_rpm),
			r.slip_rpm_mean, r.slip_rpm_peak, r.slip_pct_peak, r.end_reason, ref_text, r.top_speed_status])
	lines.append("")
	if report.reference.is_empty():
		lines.append("No online reference for this preset.")
	else:
		var ref: Dictionary = report.reference
		lines.append("Reference: %s (%s). Peak power %.1f hp at %d rpm, peak torque %.1f N·m at %d rpm. Source: %s" % [
			ref.title, ref.basis, ref.peak_power_hp, roundi(ref.peak_power_rpm), ref.peak_torque_nm, roundi(ref.peak_torque_rpm), ref.source_url])
	return "\n".join(lines) + "\n"


# The wheel estimate against the reference: peaks, peak rpm and the curve. Empty when there is no reference.
static func _online_lines(report: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var o: Dictionary = report.online
	if o.is_empty():
		return out
	out.append("  Wheel estimate (%.0f%% drivetrain) vs reference:" % (EngineSim.DRIVE_EFFICIENCY * 100.0))
	out.append("    Peak power %.2f hp at %d rpm (%+.1f%%): %s" % [o.power_hp, roundi(o.power_rpm), o.power_error * 100.0, _ok(o.power_pass)])
	out.append("    Peak torque %.2f N·m (%+.1f%%): %s" % [o.torque_nm, o.torque_error * 100.0, _ok(o.torque_pass)])
	out.append("    Peak power rpm: %s" % _ok(o.peak_rpm_pass))
	if o.curve_points_compared > 0:
		out.append("    Curve: RMS %.1f%%, max %.1f%% of peak over %d points: %s" % [
			float(o.curve_power_rmse_fraction) * 100.0, float(o.curve_power_max_error_fraction) * 100.0, o.curve_points_compared, _ok(o.curve_pass)])
	else:
		out.append("    Curve: no reference points: not checked")
	return out


static func _ok(pass_value: bool) -> String:
	return "pass" if pass_value else "FAIL"


static func to_csv(report: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append("gear,torque_nm,torque_rpm,hp,hp_rpm,top_kmh,top_kmh_rpm,end_reason,slip_mean_rpm,slip_peak_rpm,slip_peak_pct,slip_samples,reference_kmh,top_speed_error,top_speed_status")
	for r in report.gears:
		lines.append("%d,%.3f,%.0f,%.3f,%.0f,%.2f,%.0f,%s,%.2f,%.2f,%.3f,%.0f,%.2f,%.4f,%s" % [
			r.gear, r.torque_nm, r.torque_rpm, r.hp, r.hp_rpm, r.top_kmh, r.top_kmh_rpm, r.end_reason,
			r.slip_rpm_mean, r.slip_rpm_peak, r.slip_pct_peak, r.slip_samples, r.reference_kmh, r.top_speed_error, r.top_speed_status])
	return "\n".join(lines) + "\n"


# Writes the report as .txt, .md and .csv under user://dyno_reports. Returns the absolute paths written.
static func write(report: Dictionary) -> PackedStringArray:
	DirAccess.make_dir_recursive_absolute(DIR)
	var stem := "%s/%s_%s" % [DIR, report.conditions.preset_id, report.created]
	var paths := PackedStringArray()
	for pair in [[".txt", to_text(report)], [".md", to_markdown(report)], [".csv", to_csv(report)]]:
		var path: String = stem + pair[0]
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file != null:
			file.store_string(pair[1])
			file.close()
			paths.append(ProjectSettings.globalize_path(path))
	return paths


static func _stamp() -> String:
	var t := Time.get_datetime_dict_from_system()
	return "%04d%02d%02d-%02d%02d%02d" % [t.year, t.month, t.day, t.hour, t.minute, t.second]
