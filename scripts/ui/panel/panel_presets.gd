class_name PanelPresets
extends RefCounted

# PanelPresets: panel_presets.gd, moved out of ControlPanel. Each function takes the panel first and works on its members.

# The engine that was applied last, so the game opens with it again.
const LAST_ENGINE_FILE := "user://last_engine.cfg"


static func last_engine() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(LAST_ENGINE_FILE) != OK:
		return ""
	return str(cfg.get_value("engine", "last_preset", ""))


static func remember_engine(id: String) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("engine", "last_preset", id)
	cfg.save(LAST_ENGINE_FILE)


static func select_preset(panel: ControlPanel, index: int) -> void:
	if index >= panel._preset_ids.size():
		return
	var id: String = panel._preset_ids[index]
	var library: Dictionary = ControlPanel.ENGINE_LIBRARY.get_instance().get_library()
	if library.is_empty() or not library.has(id):
		return
	var p: Dictionary = library[id]
	panel._preset_button.select(index) # the dropdown shows the preset that is applied, however it was chosen
	panel._preset_button.tooltip_text = str(p.get("display_name", id))
	panel._vehicle_settings = p
	remember_engine(id)

	# ---- Set every schema-driven control from the preset ----
	for key in PanelSchema.all_keys():
		var def: Dictionary = PanelSchema.get_def(key)
		if (def.get("type", "") == "special"):
			continue
		var preset_key: String = def.get("preset_key", "")
		var value: Variant = p.get(preset_key) if preset_key != "" else null
		if value == null:
			value = def.get("default")
		if (def.type == "spin"):
			var box: SpinBox = panel._controls[key]
			var val: float = 0.0
			if value != null:
				val = float(value)
				if (key == "qs_cut_base" or key == "qs_blip_time") and val < 1.0:
					val *= 1000.0
			else:
				val = float(def.get("default", 0.0))
			panel._set_quiet(box, val)
		elif (def.type == "option"):
			var option: OptionButton = panel._controls[key]
			if key == "fuel":
				var kind_str: String = str(value) if value != null else "ron95"
				var kind_idx := FuelTank.KINDS.find(kind_str)
				option.select(max(kind_idx, 0))
			elif key == "intake_display":
				var label: String = "Velocity stack" if str(value) == "velocity_stack" else "Stock"
				panel._select_text(option, label)
			elif key == "live_exhaust_physics":
				option.select(1 if (value != null and bool(value)) else 0)
			else:
				if value != null:
					panel._select_text(option, str(value))
				else:
					option.select(def.get("default_index", 0))
		elif (def.type == "toggle"):
			var toggle: ToggleSwitch = panel._controls[key]
			toggle.select(1 if (value != null and bool(value)) else 0)

	# ---- Special controls that need extra logic ----
	var twin: OptionButton = panel._controls["twin"]
	var custom_pin: SpinBox = panel._controls["custom_pin"]
	var pin := float(p.get("twin_pin_deg", 360.0))
	if pin in [180.0, 270.0, 360.0]:
		panel._select_text(twin, str(int(pin)))
	else:
		panel._set_quiet(custom_pin, pin)
		panel._select_text(twin, "Custom")

	panel._controls["crank"].select(0)

	# ---- Plain vars (not on screen, set by preset) ----
	panel.rod_ratio = p.get("rod_ratio", 1.6)
	panel.compression_ratio = p.get("compression_ratio", 11.3)
	panel.crossplane = p.get("crossplane", false)
	panel.fire_deg = p.get("fire_deg", [])
	panel.bank_angle = p.get("bank_angle", 90.0)
	panel._set_quiet(panel._controls["bank_angle"], panel.bank_angle)
	panel._controls["shared_pins"].select(1 if p.get("shared_v_crankpins", false) else 0)
	panel.vehicle_kg = p.get("vehicle_kg", 215.0)
	# gearbox: K45R values unless the preset gives its own
	panel.primary_ratio = p.get("primary_ratio", 3.26)
	panel.exhaust_valve_mm = p.get("exhaust_valve_mm", 17.0)
	panel.wall_heat_scale = p.get("wall_heat_scale", 1.0)
	panel.valve_cd = p.get("valve_cd", 0.7)
	panel.final_drive = p.get("final_drive", 3.0)
	panel.gear_ratios = p.get("gear_ratios", Gearbox.ratios())

	panel._refresh_feature_switches()
	panel._refresh_twin() # set_quiet does not signal, so update the crank-pin row here
	panel.changed.emit()
