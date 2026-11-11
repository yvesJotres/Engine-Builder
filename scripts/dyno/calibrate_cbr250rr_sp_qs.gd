extends SceneTree

# Calibrate Honda CBR250RR SP QS: run dyno sweep and compare to published specs
# Published: 42 hp @ 13,000 rpm, 25 Nm @ 11,000 rpm, redline 14,000 rpm

const DT := 1.0 / 60.0

var _fails := 0

func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: " + msg)
	else:
		print("PASS: " + msg)

func _zeros(size: int) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(size)
	for i in size:
		out[i] = 0.0
	return out

func _init() -> void:
	var spec := EngineSpec.new()
	
	# Load preset from JSON
	var file := FileAccess.open("res://assets/engines/honda_cbr250rr_sp_qs.json", FileAccess.READ)
	if file == null:
		print("FAIL: Could not open preset file")
		quit(1)
	var json_str: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(json_str)
	if not (parsed is Dictionary):
		print("FAIL: Invalid JSON")
		quit(1)
	var data: Dictionary = parsed
	
	# Flatten preset like Presets.gd does
	var flat: Dictionary = {}
	if data.has("display_name"):
		flat["display_name"] = data["display_name"]
	for section in ["geometry", "valvetrain", "drivetrain", "ecu"]:
		if data.has(section):
			for key in data[section]:
				flat[key] = data[section][key]
	if int(data.get("metadata", {}).get("revision", 0)) > 0:
		flat["preset_revision"] = int(data.metadata.revision)
	if data.has("ecu") and data["ecu"].has("binary_path"):
		flat["ecu_binary"] = data["ecu"]["binary_path"]
	
	# Apply to spec
	var display_name: String = ""
	for key in flat:
		if key in spec:
			spec.set(key, flat[key])
		elif key == "display_name":
			display_name = flat[key]
	
	print("=== Honda CBR250RR SP QS Calibration ===")
	print("Preset: " + display_name)
	print("Displacement: %.1f cc" % spec.displacement_cc)
	print("Bore x Stroke: %.1f x %.1f mm" % [spec.bore_mm, spec.stroke_mm])
	print("Compression: %.1f:1" % spec.compression_ratio)
	print("Redline: %.0f rpm" % spec.redline_rpm)
	print("Idle target: %.0f rpm" % spec.idle_target_rpm)
	print("Quickshifter: %s" % str(spec.quickshifter))
	print("ECU binary: %s" % spec.ecu_binary)
	print("")
	
	# Validation
	var warn := spec.validation_warning()
	if warn != "":
		print("WARNING: " + warn)
	else:
		print("Spec validation: OK")
	
	# Run dyno test
	var sim := EngineSim.new()
	var dyno := DynoTest.new()
	dyno.max_gears = 0  # all gears
	dyno.reference_id = "honda_cbr250rr_sp_qs"
	
	print("Starting dyno sweep...")
	dyno.start(spec, sim)
	
	var done := false
	var frame := 0
	while not done:
		dyno.advance(DT, sim, spec, 1.0, true)
		frame += 1
		if frame % 60 == 0:
			print("  Frame %d: Phase=%s RPM=%.0f" % [frame, dyno.phase, sim.rpm])
		if not dyno.active():
			done = true
		if frame > 10000:  # safety timeout
			print("FAIL: Dyno timeout")
			break
	
	var result := dyno.result()
	
	print("")
	print("=== Dyno Results ===")
	print("Status: " + result.status)
	print("OK: %s" % str(result.ok))
	print("SAE Factor: %.4f" % result.sae_factor)
	print("Speed kind: %s" % result.speed_kind)
	print("End reason: %s" % result.speed_end_reason)
	
	if result.peak_torque:
		print("")
		print("Peak Torque: %.2f Nm @ %.0f rpm (corrected: %.2f Nm)" % [
			result.peak_torque.torque, result.peak_torque.rpm, result.peak_torque.corrected])
		print("  Stdev: %.3f, Samples: %.0f" % [result.peak_torque.stdev, result.peak_torque.samples])
	
	if result.peak_hp:
		print("")
		print("Peak Power: %.2f hp @ %.0f rpm (corrected: %.2f hp)" % [
			result.peak_hp.hp, result.peak_hp.rpm, result.peak_hp.corrected])
		print("  Stdev: %.3f, Samples: %.0f" % [result.peak_hp.stdev, result.peak_hp.samples])
	
	print("")
	print("=== Comparison to Published Specs ===")
	print("Published: 42 hp @ 13,000 rpm, 25 Nm @ 11,000 rpm")
	
	if result.peak_hp:
		var hp_error_pct = abs(result.peak_hp.corrected - 42.0) / 42.0 * 100.0
		var hp_rpm_error = abs(result.peak_hp.rpm - 13000.0)
		print("Power: %.2f hp @ %.0f rpm (target 42 hp @ 13000 rpm)" % [result.peak_hp.corrected, result.peak_hp.rpm])
		print("  Power error: %.1f%%, RPM error: %.0f rpm" % [hp_error_pct, hp_rpm_error])
		check(hp_error_pct < 5.0, "Power within 5%% of published (%.1f%%)" % hp_error_pct)
		check(hp_rpm_error < 500.0, "Peak power RPM within 500 of published (%.0f rpm)" % hp_rpm_error)
	
	if result.peak_torque:
		var tq_error_pct = abs(result.peak_torque.corrected - 25.0) / 25.0 * 100.0
		var tq_rpm_error = abs(result.peak_torque.rpm - 11000.0)
		print("Torque: %.2f Nm @ %.0f rpm (target 25 Nm @ 11000 rpm)" % [result.peak_torque.corrected, result.peak_torque.rpm])
		print("  Torque error: %.1f%%, RPM error: %.0f rpm" % [tq_error_pct, tq_rpm_error])
		check(tq_error_pct < 5.0, "Torque within 5%% of published (%.1f%%)" % tq_error_pct)
		check(tq_rpm_error < 500.0, "Peak torque RPM within 500 of published (%.0f rpm)" % tq_rpm_error)
	
	# Redline check
	var actual_redline := 0.0
	for g in result.gears:
		if g.hp > 0:
			actual_redline = max(actual_redline, g.hp_rpm)
	print("Actual redline reached: %.0f rpm (target 14000 rpm)" % actual_redline)
	check(abs(actual_redline - 14000.0) < 500.0, "Redline within 500 rpm of published")
	
	# Gear speeds
	print("")
	print("=== Gear Speeds ===")
	for g in result.gears:
		print("Gear %d: %.1f km/h, %.2f Nm @ %.0f rpm, %.2f hp @ %.0f rpm (samples: %.0f)" % [
			g.gear, g.kmh, g.torque, g.torque_rpm, g.hp, g.hp_rpm, g.samples])
	
	# Save results
	DynoTest.write_result(result, "user://dyno_cbr250rr_sp_qs")
	print("")
	print("Results saved to user://dyno_cbr250rr_sp_qs.json/.csv")
	
	print("")
	print("Tests finished, failures: %d" % _fails)
	quit(1 if _fails > 0 else 0)