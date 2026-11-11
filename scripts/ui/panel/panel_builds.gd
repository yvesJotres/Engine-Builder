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


# Saves the bike on screen under the typed name. A name that is already saved asks first, and is replaced only on yes.
static func save_build(panel: ControlPanel) -> void:
	var build_name := panel._build_name.text.strip_edges()
	if build_name.is_empty() or build_name.contains("]") or build_name.contains("[") or build_name.contains("\n"):
		panel._build_status.text = "Enter a build name without brackets."
		return
	var config := ConfigFile.new()
	config.load(panel.builds_path)
	if config.has_section(build_name):
		panel._confirm_overwrite(build_name)
		return
	write_build(panel, build_name)


# Renames the selected build to the name typed above. Refuses a name that is already saved, so nothing is lost.
static func rename_build(panel: ControlPanel) -> void:
	if panel._builds.selected < 0:
		panel._build_status.text = "Select a build to rename."
		return
	var old_name := panel._builds.get_item_text(panel._builds.selected)
	var new_name := panel._build_name.text.strip_edges()
	if new_name.is_empty() or new_name.contains("]") or new_name.contains("[") or new_name.contains("\n"):
		panel._build_status.text = "Enter a build name without brackets."
		return
	var config := ConfigFile.new()
	config.load(panel.builds_path)
	if new_name == old_name:
		return
	if config.has_section(new_name):
		panel._build_status.text = "A build named %s already exists." % new_name
		return
	for key in config.get_section_keys(old_name):
		config.set_value(new_name, key, config.get_value(old_name, key))
	config.erase_section(old_name)
	var err := config.save(panel.builds_path)
	panel._build_status.text = "Renamed to " + new_name if err == OK else "Could not rename build (error %d)." % err
	if err == OK:
		panel._refresh_builds(new_name)


# Asks before a build is deleted; the delete happens only on confirm.
static func confirm_delete(panel: ControlPanel) -> void:
	if panel._builds.selected < 0:
		panel._build_status.text = "Select a build to delete."
		return
	panel._confirm_delete(panel._builds.get_item_text(panel._builds.selected))


static func delete_build(panel: ControlPanel, build_name: String) -> void:
	var config := ConfigFile.new()
	config.load(panel.builds_path)
	config.erase_section(build_name)
	var err := config.save(panel.builds_path)
	panel._build_status.text = "Deleted: " + build_name if err == OK else "Could not delete build (error %d)." % err
	if err == OK:
		panel._refresh_builds()


static func write_build(panel: ControlPanel, build_name: String) -> void:
	var values := {}
	for key in PanelSchema.all_keys():
		var def: Dictionary = PanelSchema.get_def(key)
		if (def.type == "special"):
			continue
		var control: Control = panel._controls[key]
		if (def.type == "spin"):
			values[key] = (control as SpinBox).value
		elif (def.type == "option"):
			var option: OptionButton = control as OptionButton
			if key == "live_exhaust_physics":
				values[key] = option.selected == 1
			else:
				values[key] = option.get_item_text(option.selected)
		elif (def.type == "toggle"):
			values[key] = (control as ToggleSwitch).selected
	var config := ConfigFile.new()
	config.load(panel.builds_path)
	config.set_value(build_name, "controls", values)
	config.set_value(build_name, "preset_data", panel._vehicle_settings)
	config.set_value(build_name, "preset_id", panel._preset_ids[panel._preset_button.selected] if panel._preset_button.selected >= 0 else "")
	for key in ["rod_ratio", "compression_ratio", "crossplane", "fire_deg", "bank_angle", "vehicle_kg", "primary_ratio", "exhaust_valve_mm", "wall_heat_scale", "valve_cd", "final_drive", "gear_ratios"]:
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
	for key in ["rod_ratio", "compression_ratio", "crossplane", "fire_deg", "bank_angle", "vehicle_kg", "primary_ratio", "exhaust_valve_mm", "wall_heat_scale", "valve_cd", "final_drive", "gear_ratios"]:
		var value: Variant = config.get_value(build_name, key, panel.get(key))
		if typeof(value) == typeof(panel.get(key)):
			panel.set(key, value)
	# Builds saved before the intake valve and runner were controls kept them as plain values: move them across.
	for key in ["intake_valve_mm", "runner_length_m"]:
		if not values.has(key) and config.has_section_key(build_name, key):
			values[key] = config.get_value(build_name, key)
	panel._set_quiet(panel._controls["bank_angle"], panel.bank_angle)
	panel._controls["shared_pins"].select(0)
	for key in PanelSchema.all_keys():
		var def: Dictionary = PanelSchema.get_def(key)
		if (def.type == "special"):
			continue
		if not values.has(key):
			continue
		if key == "crank":
			panel._refresh_twin()
		var control: Control = panel._controls[key]
		if (def.type == "spin") and (values[key] is float or values[key] is int):
			panel._set_quiet(control, float(values[key]))
		elif (def.type == "option") and values[key] is String:
			panel._select_text(control, values[key])
		elif (def.type == "toggle") and values[key] is bool:
			control.select(1 if values[key] else 0)
	panel.bank_angle = panel._controls["bank_angle"].value
	var preset_index := panel._preset_ids.find(str(config.get_value(build_name, "preset_id", "")))
	if preset_index >= 0:
		panel._preset_button.select(preset_index)
	panel._refresh_feature_switches()
	panel._refresh_twin()
	panel._build_name.text = build_name
	panel._build_status.text = "Loaded: " + build_name
	panel.changed.emit()
