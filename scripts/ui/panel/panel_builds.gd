class_name PanelBuilds
extends RefCounted

# PanelBuilds: panel_builds.gd, moved out of ControlPanel. Each function takes the panel first and works on its members.

static func refresh(panel: ControlPanel, selected := "") -> void:
	var config := ConfigFile.new()
	config.load(panel.builds_path)
	panel._builds.clear()
	var names := config.get_sections()
	names.sort()
	for build_name in names:
		panel._builds.add_item(build_name)
	if not selected.is_empty() and names.has(selected):
		panel._builds.select(names.find(selected))
	panel._builds.disabled = names.is_empty()


static func save_build(panel: ControlPanel) -> void:
	var build_name := panel._build_name.text.strip_edges()
	if build_name.is_empty() or build_name.contains("]") or build_name.contains("[") or build_name.contains("\n"):
		panel._build_status.text = "Enter a build name without brackets."
		return
	var values := {}
	for key in panel._controls:
		var control: Control = panel._controls[key]
		if control is SpinBox:
			values[key] = control.value
		elif control is OptionButton or control is ToggleSwitch:
			values[key] = control.get_item_text(control.selected)
	var config := ConfigFile.new()
	config.load(panel.builds_path)
	config.set_value(build_name, "controls", values)
	config.set_value(build_name, "preset_data", panel._vehicle_settings)
	config.set_value(build_name, "preset_id", panel._preset_ids[panel._preset_button.selected] if panel._preset_button.selected >= 0 else "")
	for key in ["rod_ratio", "compression_ratio", "crossplane", "fire_deg", "bank_angle", "vehicle_kg", "primary_ratio", "intake_valve_mm", "exhaust_valve_mm", "runner_length_m", "wall_heat_scale", "valve_cd", "final_drive", "gear_ratios"]:
		config.set_value(build_name, key, panel.get(key))
	var err := config.save(panel.builds_path)
	panel._build_status.text = "Saved: " + build_name if err == OK else "Could not save build (error %d)." % err
	if err == OK:
		panel._refresh_builds(build_name)


static func load_build(panel: ControlPanel) -> void:
	if panel._builds.selected < 0:
		return
	var build_name := panel._builds.get_item_text(panel._builds.selected)
	var config := ConfigFile.new()
	if config.load(panel.builds_path) != OK:
		panel._build_status.text = "Could not load builds."
		return
	var values: Variant = config.get_value(build_name, "controls", {})
	var preset_data: Variant = config.get_value(build_name, "preset_data", {})
	if not values is Dictionary or not preset_data is Dictionary:
		panel._build_status.text = "Build data is invalid."
		return
	# Reset from the saved bike before restoring overrides, not the bike currently
	# on screen. Older saves may omit newer controls and capability declarations.
	var saved_id := str(config.get_value(build_name, "preset_id", ""))
	var saved_index := panel._preset_ids.find(saved_id)
	if saved_index >= 0:
		panel._on_preset_selected(saved_index)
	var reference: Dictionary = ControlPanel.ENGINE_LIBRARY.get_instance().get_library().get(saved_id, {})
	panel._vehicle_settings = preset_data.duplicate(true)
	for key in ["throttle_bore_mm", "throttle_count", "runner_bore_mm", "rider_kg", "vehicle_mass_includes_rider"]:
		if not panel._vehicle_settings.has(key) and reference.has(key):
			panel._vehicle_settings[key] = reference[key]
	for key in ["wheelbase_mm", "front_tire_width_mm", "rear_tire_width_mm", "front_tire_aspect", "rear_tire_aspect", "front_rim_in", "rear_rim_in"]:
		if not panel._vehicle_settings.has(key) and reference.has(key):
			panel._vehicle_settings[key] = reference[key]
	for capability in ["has_quickshifter", "has_launch_control", "has_abs", "has_traction_control"]:
		panel._vehicle_settings[capability] = bool(preset_data.get(capability, reference.get(capability, false)))
	# Historical builds used a different control key for the quickshifter switch.
	if not values.has("qs_enabled") and values.has("quickshifter"):
		values["qs_enabled"] = values["quickshifter"]
	for key in ["qs_enabled", "launch_control", "abs_enabled", "traction_control_enabled"]:
		panel._controls[key].select(0)
	for key in ["rod_ratio", "compression_ratio", "crossplane", "fire_deg", "bank_angle", "vehicle_kg", "primary_ratio", "intake_valve_mm", "exhaust_valve_mm", "runner_length_m", "wall_heat_scale", "valve_cd", "final_drive", "gear_ratios"]:
		var value: Variant = config.get_value(build_name, key, panel.get(key))
		if typeof(value) == typeof(panel.get(key)):
			panel.set(key, value)
	panel._set_quiet(panel._controls["bank_angle"], panel.bank_angle)
	panel._controls["shared_pins"].select(0)
	for key in panel._controls:
		if not values.has(key):
			continue
		if key == "crank":
			panel._refresh_twin()
		var control: Control = panel._controls[key]
		if control is SpinBox and (values[key] is float or values[key] is int):
			panel._set_quiet(control, values[key])
		elif (control is OptionButton or control is ToggleSwitch) and values[key] is String:
			panel._select_text(control, values[key])
	panel.bank_angle = panel._controls["bank_angle"].value
	var preset_index := panel._preset_ids.find(str(config.get_value(build_name, "preset_id", "")))
	if preset_index >= 0:
		panel._preset_button.select(preset_index)
	panel._refresh_feature_switches()
	panel._refresh_twin()
	panel._build_name.text = build_name
	panel._build_status.text = "Loaded: " + build_name
	panel.changed.emit()
