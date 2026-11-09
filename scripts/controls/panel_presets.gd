class_name PanelPresets
extends RefCounted

# PanelPresets: panel_presets.gd, moved out of ControlPanel. Each function takes the panel first and works on its members.

static func select_preset(panel: ControlPanel, index: int) -> void:
	if index >= panel._preset_ids.size():
		return
	var id: String = panel._preset_ids[index]
	var library: Dictionary = ControlPanel.ENGINE_LIBRARY.get_instance().get_library()
	if library.is_empty() or not library.has(id):
		return
	var p: Dictionary = library[id]
	panel._preset_button.select(index) # the dropdown shows the preset that is applied, however it was chosen
	panel._vehicle_settings = p
	panel._preset_button.tooltip_text = str(p.get("display_name", id))
	panel._set_quiet(panel._controls["cyl"], p.cylinders)
	panel._set_quiet(panel._controls["bore"], p.bore_mm)
	panel._set_quiet(panel._controls["stroke"], p.stroke_mm)
	panel._set_quiet(panel._controls["slant"], p.get("slant_deg", 20.0))
	panel._select_text(panel._controls["layout"], p.layout)
	panel._select_text(panel._controls["stroke_type"], p.get("stroke_type", "four_stroke"))
	panel._select_text(panel._controls["header"], p.header)
	panel._select_text(panel._controls["muffler_style"], p.get("muffler_style", "stock"))
	panel._controls["live_exhaust_physics"].select(1 if p.get("live_exhaust_physics", false) else 0)
	panel._select_text(panel._controls["intake_display"], "Velocity stack" if p.get("intake_display", "stock") == "velocity_stack" else "Stock")
	panel._set_quiet(panel._controls["stack_length"], p.get("velocity_stack_length_mm", 70.0))
	panel._controls["fuel"].select(FuelTank.KINDS.find(p.fuel))
	var pin := float(p.get("twin_pin_deg", 360.0))
	if pin in [180.0, 270.0, 360.0]:
		panel._select_text(panel._controls["twin"], str(int(pin)))
	else:
		panel._set_quiet(panel._controls["custom_pin"], pin)
		panel._select_text(panel._controls["twin"], "Custom")
	panel._set_quiet(panel._controls["boost_ratio"], p.get("max_boost_ratio", 1.0))
	panel._set_quiet(panel._controls["boost_time"], p.get("boost_spool_time", 0.6))
	panel._set_quiet(panel._controls["compressor_battery"], p.get("compressor_battery_wh", 40.0))
	panel._set_quiet(panel._controls["compressor_power"], p.get("compressor_power_w", 2000.0))
	panel._set_quiet(panel._controls["compressor_charge"], p.get("compressor_charge_w", 1000.0))
	panel._set_quiet(panel._controls["redline"], p.redline_rpm)
	panel._controls["speed_limit_enabled"].select(1 if p.get("speed_limit_enabled", false) else 0)
	panel._set_quiet(panel._controls["speed_limit_kmh"], p.get("speed_limit_kmh", 300.0))
	panel._set_quiet(panel._controls["flywheel"], p.flywheel_kg)
	panel._set_quiet(panel._controls["flywheel_r"], p.flywheel_radius_mm)
	# the cams and timing go back to the stock values (or the preset's own) when a preset is picked
	panel._set_quiet(panel._controls["in_dur"], p.get("intake_duration_deg", 240.0))
	panel._set_quiet(panel._controls["in_lift"], p.get("intake_lift_mm", 6.0))
	panel._set_quiet(panel._controls["in_centre"], p.get("intake_centre_deg", 470.0))
	panel._set_quiet(panel._controls["ex_dur"], p.get("exhaust_duration_deg", 230.0))
	panel._set_quiet(panel._controls["ex_lift"], p.get("exhaust_lift_mm", 5.0))
	panel._set_quiet(panel._controls["ex_centre"], p.get("exhaust_centre_deg", 255.0))
	panel._set_quiet(panel._controls["timing"], 0.0)
	panel._set_quiet(panel._controls["idle"], p.get("idle_target_rpm", 1200.0))
	panel.rod_ratio = p.rod_ratio
	panel.compression_ratio = p.get("compression_ratio", 11.3)
	panel.crossplane = p.get("crossplane", false)
	panel.fire_deg = p.get("fire_deg", [])
	panel._controls["crank"].select(0)
	panel.bank_angle = p.get("bank_angle", 90.0)
	panel._set_quiet(panel._controls["bank_angle"], panel.bank_angle)
	panel._controls["shared_pins"].select(1 if p.get("shared_v_crankpins", false) else 0)
	panel.vehicle_kg = p.get("vehicle_kg", 215.0)
	# gearbox: K45R values unless the preset gives its own
	panel.primary_ratio = p.get("primary_ratio", 3.26)
	panel.intake_valve_mm = p.get("intake_valve_mm", 20.0)
	panel.exhaust_valve_mm = p.get("exhaust_valve_mm", 17.0)
	panel.runner_length_m = p.get("runner_length_m", 0.25)
	panel.wall_heat_scale = p.get("wall_heat_scale", 1.0)
	panel.valve_cd = p.get("valve_cd", 0.7)
	panel.final_drive = p.get("final_drive", 3.0)
	panel.gear_ratios = p.get("gear_ratios", Gearbox.ratios())
	# Feature switches reflect fitted hardware, never stale controls from another bike.
	panel._select_text(panel._controls["power_mode"], p.get("power_mode", "F"))
	panel._controls["qs_enabled"].select(1 if p.get("quickshifter", false) else 0)
	panel._controls["launch_control"].select(1 if p.get("launch_control", false) else 0)
	panel._controls["abs_enabled"].select(1 if p.get("abs_enabled", false) else 0)
	panel._controls["traction_control_enabled"].select(1 if p.get("traction_control_enabled", false) else 0)
	panel._controls["slipper_clutch"].select(1 if p.get("slipper_clutch", false) else 0)
	panel._refresh_feature_switches()
	panel._refresh_twin() # set_quiet does not signal, so update the crank-pin row here
	panel.changed.emit()
