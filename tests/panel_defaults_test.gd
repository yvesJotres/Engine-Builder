extends SceneTree

# The control panel builds the engine's settings in the game. For the default engine and for every preset, what the panel hands
# over must equal what the spec would hold from the preset alone: a slider whose range does not contain its value is clamped
# silently, and the engine then differs from every test that builds its spec directly.
# Run: godot --headless -s tests/panel_defaults_test.gd (exit code 1 on failure)

const FIELDS := ["cylinders", "bore_mm", "stroke_mm", "redline_rpm", "flywheel_kg", "flywheel_radius_mm", "fuel",
		"intake_centre_deg", "intake_duration_deg", "intake_lift_mm", "exhaust_centre_deg", "exhaust_duration_deg",
		"exhaust_lift_mm", "ignition_offset_deg", "idle_target_rpm", "compression_ratio", "crossplane"]

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func _same(a, b) -> bool:
	if typeof(a) == TYPE_FLOAT or typeof(b) == TYPE_FLOAT:
		return absf(float(a) - float(b)) < 0.001
	return a == b


func _init() -> void:
	await process_frame
	var panel := ControlPanel.new()
	root.add_child(panel)
	await process_frame
	# the default engine, before any preset is chosen
	var from_panel := EngineSpec.new()
	panel.apply_to(from_panel)
	var defaults := EngineSpec.new()
	for field in FIELDS:
		if field in ["compression_ratio", "crossplane"]:
			continue # set by a preset, not by a slider
		check(_same(from_panel.get(field), defaults.get(field)), "default engine: %s is %s from the panel, %s in the spec" % [field, str(from_panel.get(field)), str(defaults.get(field))])
	# every preset
	var index := 0
	for name in Presets.PRESETS:
		panel._on_preset_selected(index)
		var got := EngineSpec.new()
		panel.apply_to(got)
		var want := EngineSpec.new()
		for key in Presets.PRESETS[name]:
			want.set(key, Presets.PRESETS[name][key])
		for field in FIELDS:
			check(_same(got.get(field), want.get(field)), "%s: %s is %s from the panel, %s from the preset" % [name, field, str(got.get(field)), str(want.get(field))])
		check(got.validation_warning() == "", "%s: the panel's settings pass validation (%s)" % [name, got.validation_warning()])
		index += 1
	print("checked the default engine and %d presets" % Presets.PRESETS.size())
	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
