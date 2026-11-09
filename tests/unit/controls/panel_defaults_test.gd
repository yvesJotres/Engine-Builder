extends SceneTree

# The control panel builds the engine's settings in the game. For the default engine and for every preset, what the panel hands
# over must equal what the spec would hold from the preset alone: a slider whose range does not contain its value is clamped
# silently, and the engine then differs from every test that builds its spec directly.
# Run: godot --headless -s tests/unit/controls/panel_defaults_test.gd (exit code 1 on failure)

const FIELDS := ["cylinders", "bore_mm", "stroke_mm", "redline_rpm", "flywheel_kg", "flywheel_radius_mm", "fuel", "runner_bore_mm",
		"intake_centre_deg", "intake_duration_deg", "intake_lift_mm", "exhaust_centre_deg", "exhaust_duration_deg",
		"exhaust_lift_mm", "ignition_offset_deg", "idle_target_rpm", "compression_ratio", "crossplane", "layout",
		"vehicle_type", "transmission_type", "wheelbase_mm", "wheel_radius_m", "vehicle_length_mm", "vehicle_width_mm", "vehicle_height_mm", "front_track_mm", "rear_track_mm", "front_wheel_radius_m", "front_tire_width_mm", "rear_tire_width_mm", "fuel_capacity_l", "drag_area_m2", "max_boost_ratio", "has_quickshifter", "has_launch_control", "has_abs", "has_traction_control", "quickshifter", "launch_control", "abs_enabled", "traction_control_enabled", "speed_limit_enabled", "speed_limit_kmh"]

const VALVE_FIELDS := ["intake_centre_deg", "intake_duration_deg", "intake_lift_mm", "exhaust_centre_deg", "exhaust_duration_deg", "exhaust_lift_mm"]

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
	var library = EngineLibrary.get_instance()
	library._library = Presets.PRESETS
	library._ready = true
	var panel := ControlPanel.new()
	root.add_child(panel)
	await process_frame
	check(not panel._preset_button.disabled and panel._preset_button.item_count == Presets.PRESETS.size(), "already-loaded library populates the preset selector")
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
			# a two-stroke has no valves or cams, so its valve controls are not compared
			if got.stroke_type == "two_stroke" and field in VALVE_FIELDS:
				continue
			check(_same(got.get(field), want.get(field)), "%s: %s is %s from the panel, %s from the preset" % [name, field, str(got.get(field)), str(want.get(field))])
		check(panel._controls["qs_enabled"].visible, "%s: quickshifter switch is on every bike" % name)
		check(panel._controls["launch_control"].visible, "%s: launch-control switch is on every bike" % name)
		check(panel._controls["abs_enabled"].visible == (got.has_abs and ControlPanel.WHEEL_AIDS_AVAILABLE), "%s: ABS switch requires fitted hardware and implemented wheel physics" % name)
		check(panel._controls["traction_control_enabled"].visible == (got.has_traction_control and ControlPanel.WHEEL_AIDS_AVAILABLE), "%s: traction-control switch requires fitted hardware and implemented wheel physics" % name)
		check(got.validation_warning() == "", "%s: the panel's settings pass validation (%s)" % [name, got.validation_warning()])
		index += 1
	var frame := panel.get_child(0) as PanelContainer
	var scroll := _find_scroll(frame)
	check(is_equal_approx(frame.anchor_bottom, 1.0), "panel tracks viewport height")
	frame.anchor_bottom = 0.0
	frame.offset_bottom = 376.0
	await process_frame
	await process_frame
	var scrollbar := scroll.get_v_scroll_bar()
	check(scrollbar.max_value > scrollbar.page, "short panel can scroll to its lower controls")
	scroll.scroll_vertical = int(scrollbar.max_value - scrollbar.page)
	check(scroll.scroll_vertical > 0, "short panel scroll position changes")
	print("checked the default engine and %d presets" % Presets.PRESETS.size())
	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)

# The scrolling page area, wherever the layout puts it.
func _find_scroll(node: Node) -> ScrollContainer:
	for child in node.get_children():
		if child is ScrollContainer:
			return child
		var inner := _find_scroll(child)
		if inner != null:
			return inner
	return null
