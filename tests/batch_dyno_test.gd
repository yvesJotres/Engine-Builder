extends SceneTree

# Runs the dyno test on every engine in Presets.PRESETS
# Run: godot --headless -s tests/batch_dyno_test.gd (exit code 1 on any failure)

var _fails := 0
var _results := []

func check(ok: bool, msg: String) -> void:
	print(("ok   " if ok else "FAIL ") + msg)
	if not ok:
		_fails += 1

func _apply_preset(spec: EngineSpec, preset: Dictionary) -> void:
	for key in preset:
		spec.set(key, preset[key])

func _init() -> void:
	var presets_dict := Presets.PRESETS
	print("Found %d engine presets" % presets_dict.size())
	
	for engine_name in presets_dict:
		var preset: Dictionary = presets_dict[engine_name]
		print("\n===== %s =====" % engine_name)
		
		var spec := EngineSpec.new()
		_apply_preset(spec, preset)
		
		# Print key specs
		print("  Cylinders: %d, Displacement: %.1f cc, Bore: %.1f mm, Stroke: %.1f mm" % [
			preset.cylinders, preset.displacement_cc, preset.bore_mm, preset.stroke_mm
		])
		print("  Redline: %.0f rpm, Fuel: %s" % [preset.redline_rpm, preset.fuel])
		
		var sim := EngineSim.new()
		sim.physics_dt = 1.0 / 1200.0
		var dyno := DynoTest.new()
		dyno.start(spec, sim)
		var frame := 1.0 / 60.0
		var frames := 0
		# Adaptive max time: longer for low-redline engines (fewer rpm bins, slower accel)
		var max_frames := 60 * 900
		if spec.redline_rpm < 8000:
			max_frames = 60 * 1800  # 30 min for low-redline
		elif spec.redline_rpm > 14000:
			max_frames = 60 * 1200  # 20 min for very high redline
		
		while dyno.active() and frames < max_frames:
			dyno.advance(frame, sim, spec, 1.0, true)
			frames += 1
		
		var r := dyno.result()
		print("  Finished after %.0f s sim time: %s" % [frames * frame, dyno.status])
		
		check(dyno.phase == DynoTest.Phase.DONE, "  Test runs to its end")
		check(dyno.ok, "  Test finished without fault")
		# Adaptive curve threshold: low-redline engines have fewer rpm bins
		var min_curve_points := 20
		if spec.redline_rpm < 6000:
			min_curve_points = 3
		elif spec.redline_rpm < 8000:
			min_curve_points = 10
		elif spec.redline_rpm < 12000:
			min_curve_points = 15
		check(r.curve.size() >= min_curve_points, "  Curve has points across rev range (%d, need %d)" % [r.curve.size(), min_curve_points])
		
		var pt: Dictionary = r.peak_torque
		var ph: Dictionary = r.peak_hp
		print("  Peak torque %.2f N·m at %.0f rpm, Peak power %.2f hp at %.0f rpm" % [pt.torque, pt.rpm, ph.hp, ph.rpm])
		
		var gears_run := 0
		for g in r.gears:
			if g.samples > 0.0:
				gears_run += 1
				print("  Gear %d: %.0f samples, peak %.2f N·m at %.0f rpm, %.2f hp at %.0f rpm" % [
					g.gear, g.samples, g.torque, g.torque_rpm, g.hp, g.hp_rpm
				])
		
		check(gears_run >= 1, "  At least one gear completed (%d)" % gears_run)
		
		_results.append({
			"name": engine_name,
			"peak_torque": pt.torque,
			"peak_torque_rpm": pt.rpm,
			"peak_hp": ph.hp,
			"peak_hp_rpm": ph.rpm,
			"gears_run": gears_run,
			"ok": dyno.ok
		})
	
	# Summary
	print("\n===== SUMMARY =====")
	print("%-40s %8s %8s %6s %6s" % ["Engine", "Torque", "HP", "RPM@Tq", "RPM@HP"])
	for res in _results:
		if res.ok:
			print("%-40s %8.2f %8.2f %6.0f %6.0f" % [
				res.name, res.peak_torque, res.peak_hp, res.peak_torque_rpm, res.peak_hp_rpm
			])
		else:
			print("%-40s FAILED" % res.name)
	
	print("\nRESULT: " + ("FAIL (%d failures)" % _fails if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)