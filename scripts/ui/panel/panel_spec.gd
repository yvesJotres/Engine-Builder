class_name PanelSpec
extends RefCounted

# PanelSpec: panel_spec.gd, moved out of ControlPanel. Each function takes the panel first and works on its members.

# Copies the panel's values into the engine spec.
static func apply(panel: ControlPanel, spec: EngineSpec) -> void:
	var layout: OptionButton = panel._controls["layout"]
	var header: OptionButton = panel._controls["header"]
	var fuel: OptionButton = panel._controls["fuel"]
	spec.cylinders = int(panel._controls["cyl"].value)
	spec.bore_mm = panel._controls["bore"].value
	spec.stroke_mm = panel._controls["stroke"].value
	spec.slant_deg = panel._controls["slant"].value
	# displacement is not an input: it follows from bore, stroke and cylinder count
	spec.displacement_cc = Units.displacement_cc(spec.bore_mm, spec.stroke_mm, spec.cylinders)
	spec.layout = layout.get_item_text(layout.selected)
	spec.stroke_type = panel._controls["stroke_type"].get_item_text(panel._controls["stroke_type"].selected)
	spec.induction = str(panel._vehicle_settings.get("induction", "injection"))
	spec.intake_display = "velocity_stack" if panel._controls["intake_display"].selected == 1 and spec.induction == "injection" and spec.stroke_type == "four_stroke" else "stock"
	spec.velocity_stack_length_mm = panel._controls["stack_length"].value
	var twin: OptionButton = panel._controls["twin"]
	spec.twin_pin_deg = panel._controls["custom_pin"].value if twin.get_item_text(twin.selected) == "Custom" else float(twin.get_item_text(twin.selected))
	spec.header = header.get_item_text(header.selected)
	spec.muffler_style = panel._controls["muffler_style"].get_item_text(panel._controls["muffler_style"].selected)
	spec.live_exhaust_physics = panel._controls["live_exhaust_physics"].selected == 1
	spec.fuel = FuelTank.KINDS[fuel.selected]
	spec.rod_ratio = panel.rod_ratio
	spec.compression_ratio = panel.compression_ratio
	spec.crossplane = panel.crossplane
	spec.fire_deg = panel.fire_deg
	spec.bank_angle = panel._controls["bank_angle"].value
	spec.shared_v_crankpins = spec.layout == "V" and panel._controls["shared_pins"].selected == 1
	spec.vehicle_kg = panel.vehicle_kg
	spec.primary_ratio = panel.primary_ratio
	spec.final_drive = panel.final_drive
	spec.gear_ratios = panel.gear_ratios
	var default_spec := EngineSpec.new()
	for key in ["vehicle_type", "transmission_type", "wheelbase_mm", "wheel_radius_m", "vehicle_length_mm", "vehicle_width_mm", "vehicle_height_mm", "front_track_mm", "rear_track_mm", "front_wheel_radius_m", "front_tire_width_mm", "rear_tire_width_mm", "front_tire_aspect", "rear_tire_aspect", "front_rim_in", "rear_rim_in", "fuel_capacity_l", "drag_area_m2", "max_boost_ratio", "electric_compressor", "boost_spool_time", "intake_area_scale", "manifold_volume_scale", "clutch_capacity_nm", "ecu_binary", "has_quickshifter", "has_launch_control", "has_abs", "has_traction_control"]:
		spec.set(key, panel._vehicle_settings.get(key, default_spec.get(key)))
	for key in ["throttle_bore_mm", "throttle_count", "runner_bore_mm", "rider_kg", "vehicle_mass_includes_rider"]:
		spec.set(key, panel._vehicle_settings.get(key, default_spec.get(key)))
	spec.v3r_style = bool(panel._vehicle_settings.get("v3r_style", false))
	spec.max_boost_ratio = panel._controls["boost_ratio"].value
	spec.boost_spool_time = panel._controls["boost_time"].value
	spec.compressor_battery_wh = panel._controls["compressor_battery"].value
	spec.compressor_power_w = panel._controls["compressor_power"].value
	spec.compressor_charge_w = panel._controls["compressor_charge"].value
	spec.redline_rpm = panel._controls["redline"].value
	spec.speed_limit_enabled = panel._controls["speed_limit_enabled"].selected == 1
	spec.speed_limit_kmh = panel._controls["speed_limit_kmh"].value
	spec.idle_target_rpm = panel._controls["idle"].value
	spec.flywheel_kg = panel._controls["flywheel"].value
	spec.flywheel_radius_mm = panel._controls["flywheel_r"].value
	# Valve timing only applies to four-stroke engines
	var panel_stroke_type: String = panel._controls["stroke_type"].get_item_text(panel._controls["stroke_type"].selected)
	if panel_stroke_type == "four_stroke":
		spec.intake_duration_deg = panel._controls["in_dur"].value
		spec.intake_lift_mm = panel._controls["in_lift"].value
		spec.intake_valve_mm = panel.intake_valve_mm
		spec.exhaust_valve_mm = panel.exhaust_valve_mm
		spec.runner_length_m = panel.runner_length_m
		spec.wall_heat_scale = panel.wall_heat_scale
		spec.valve_cd = panel.valve_cd
		spec.intake_centre_deg = panel._controls["in_centre"].value
		spec.exhaust_duration_deg = panel._controls["ex_dur"].value
		spec.exhaust_lift_mm = panel._controls["ex_lift"].value
		spec.exhaust_centre_deg = panel._controls["ex_centre"].value
		spec.cam_lobe_profile = int(panel._vehicle_settings.get("cam_lobe_profile", spec.cam_lobe_profile))
		spec.intake_lobe_profile = int(panel._vehicle_settings.get("intake_lobe_profile", spec.cam_lobe_profile))
		spec.exhaust_lobe_profile = int(panel._vehicle_settings.get("exhaust_lobe_profile", spec.cam_lobe_profile))
		spec.intake_open_ramp_deg = float(panel._vehicle_settings.get("intake_open_ramp_deg", 0.0))
		spec.intake_close_ramp_deg = float(panel._vehicle_settings.get("intake_close_ramp_deg", 0.0))
		spec.exhaust_open_ramp_deg = float(panel._vehicle_settings.get("exhaust_open_ramp_deg", 0.0))
		spec.exhaust_close_ramp_deg = float(panel._vehicle_settings.get("exhaust_close_ramp_deg", 0.0))
		spec.intake_duration_050_deg = float(panel._vehicle_settings.get("intake_duration_050_deg", 0.0))
		spec.exhaust_duration_050_deg = float(panel._vehicle_settings.get("exhaust_duration_050_deg", 0.0))
		spec.intake_lift_curve = panel._vehicle_settings.get("intake_lift_curve", [])
		spec.exhaust_lift_curve = panel._vehicle_settings.get("exhaust_lift_curve", [])
	# ABS and traction control apply only when the bike has them and the wheel physics is built. The other aids are on every bike.
	spec.power_mode = panel._controls["power_mode"].get_item_text(panel._controls["power_mode"].selected)
	# Quickshifter detailed controls
	spec.quickshifter = panel._controls["qs_enabled"].selected == 1
	spec.quickshifter_cut_time = panel._controls["qs_cut_base"].value / 1000.0
	spec.quickshifter_blip_time = panel._controls["qs_blip_time"].value / 1000.0
	spec.quickshifter_blip_throttle = panel._controls["qs_blip_throttle"].value
	spec.quickshifter_sensitivity = panel._controls["qs_sensitivity"].value
	spec.quickshifter_flat_shift = panel._controls["qs_flat_shift"].selected == 1
	# Build cut profile from base (simplified: scale by gear)
	spec.quickshifter_cut_profile = []
	for g in range(6):
		var base = panel._controls["qs_cut_base"].value
		var profile = [[3000, base + 10], [6000, base], [10000, base - 10]]
		# Adjust per gear
		for p in profile:
			p[1] = p[1] * (1.0 - g * 0.05)  # shorter cut in higher gears
		spec.quickshifter_cut_profile.append(profile)
	spec.launch_control = panel._controls["launch_control"].selected == 1
	spec.abs_enabled = ControlPanel.WHEEL_AIDS_AVAILABLE and panel._controls["abs_enabled"].selected == 1
	spec.traction_control_enabled = ControlPanel.WHEEL_AIDS_AVAILABLE and panel._controls["traction_control_enabled"].selected == 1
	spec.slipper_clutch = panel._controls["slipper_clutch"].selected == 1
	spec.slipper_ramp = 0.5 # fixed for now, could add a spin box later
