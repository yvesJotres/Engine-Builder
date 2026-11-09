extends SceneTree

# The Harley Sportster 883 preset: it loads and validates, it is a 45 degree V-twin with one shared crank pin (firing at 0 and 315
# degrees, so the pulses are 315 and 405 apart), the control panel keeps those settings, and a short run stays finite.
# Exits 1 on any failure. Run: godot --headless --path . -s res://tests/unit/engine/sportster_test.gd

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func _init() -> void:
	await process_frame
	var data: Dictionary = Presets.PRESETS.get("harley_sportster_883", {})
	check(not data.is_empty(), "the Sportster preset is registered")
	if data.is_empty():
		quit(1)
		return
	var spec := EngineSpec.new()
	for key in data:
		spec.set(key, data[key])
	check(spec.validation_warning().is_empty(), "the preset validates: " + spec.validation_warning())
	check(spec.cylinders == 2 and spec.layout == "V", "two cylinders in a V")
	check(absf(spec.bank_angle - 45.0) < 0.001, "45 degree bank angle")
	check(absf(spec.calc_displacement_cc() - 883.0) < 3.0, "displacement about 883 cc, got %.1f" % spec.calc_displacement_cc())
	check(spec.fire_deg.size() == 2 and absf(spec.fire_deg[1] - 315.0) < 0.001, "fires at 0 and 315 degrees")
	check(absf(spec.twin_pin_deg - 315.0) < 0.001, "crank pin at 315 degrees")
	# the two firing intervals around the 720 degree cycle
	var interval_a: float = spec.fire_deg[1] - spec.fire_deg[0]
	var interval_b: float = 720.0 - interval_a
	check(absf(interval_a - 315.0) < 0.001 and absf(interval_b - 405.0) < 0.001, "intervals are 315 and 405 degrees")

	# the control panel keeps the crank pin and firing angles through its own settings
	var panel := ControlPanel.new()
	root.add_child(panel)
	await process_frame
	var index: int = panel._preset_ids.find("harley_sportster_883")
	check(index >= 0, "the panel lists the Sportster")
	if index >= 0:
		panel._on_preset_selected(index)
		var from_panel := EngineSpec.new()
		panel.apply_to(from_panel)
		check(absf(from_panel.twin_pin_deg - 315.0) < 0.001, "the panel keeps the 315 degree crank pin, got %.1f" % from_panel.twin_pin_deg)
		check(from_panel.fire_deg == spec.fire_deg, "the panel keeps the firing angles")
	panel.free()

	# a short run from a cold start: it must stay finite and build speed
	var sim := EngineSim.new()
	sim.fuel.set_kind(spec.fuel)
	for i in 900:
		sim.step(1.0 / 60.0, spec, 0.2, true, i < 600, false, false, 1.0)
	check(is_finite(sim.rpm) and sim.rpm > 0.0, "the engine runs and rpm is finite, got %.0f" % sim.rpm)
	print("sportster_test: %s" % ("PASSED" if _fails == 0 else "FAILED"))
	quit(0 if _fails == 0 else 1)
