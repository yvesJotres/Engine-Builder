class_name PanelSpec
extends RefCounted

# PanelSpec: panel_spec.gd, moved out of ControlPanel. Each function takes the panel first and works on its members.
#
# Copies the panel's values into the engine spec. Uses PanelSchema as the single
# source of truth for the control↔spec mapping; special cases (type conversions,
# conditional logic, computed fields) are handled below the schema pass.

# Controls that need non-default handling when copying to spec.
# Key = control key, value = how to extract the value.
const SPECIAL_SPIN := {
	"cyl": "int",           # int() conversion
	"qs_cut_base": "/1000", # milliseconds to seconds
	"qs_blip_time": "/1000",# milliseconds to seconds
}
const SPECIAL_OPTION := {
	"twin": "custom",       # custom_pin if "Custom", else the item text as float
	"intake_display": "conditional", # velocity_stack only if injection + four_stroke
	"live_exhaust_physics": "selected_eq_1",
	"fuel": "fuel_kind",
}
const SPECIAL_TOGGLE := {
	"qs_flat_shift": "selected_eq_1",
	"launch_control": "selected_eq_1",
	"abs_enabled": "wheel_aids_and_selected_eq_1",
	"traction_control_enabled": "wheel_aids_and_selected_eq_1",
	"slipper_clutch": "selected_eq_1",
}

# Copies the panel's values into the engine spec.
static func apply(panel: ControlPanel, spec: EngineSpec) -> void:
	# ---- 1. Settings pass: vehicle and drivetrain settings from preset/settings ----
	var default_spec := EngineSpec.new()
	for key in ["vehicle_type", "transmission_type", "wheelbase_mm", "wheel_radius_m", "vehicle_length_mm", "vehicle_width_mm", "vehicle_height_mm", "front_track_mm", "rear_track_mm", "front_wheel_radius_m", "front_tire_width_mm", "rear_tire_width_mm", "front_tire_aspect", "rear_tire_aspect", "front_rim_in", "rear_rim_in", "fuel_capacity_l", "drag_area_m2", "electric_compressor", "intake_area_scale", "manifold_volume_scale", "clutch_capacity_nm", "ecu_binary", "has_quickshifter", "has_launch_control", "has_abs", "has_traction_control"]:
		spec.set(key, panel._vehicle_settings.get(key, default_spec.get(key)))
	for key in ["throttle_bore_mm", "throttle_count", "runner_bore_mm", "rider_kg", "vehicle_mass_includes_rider"]:
		spec.set(key, panel._vehicle_settings.get(key, default_spec.get(key)))
	spec.v3r_style = bool(panel._vehicle_settings.get("v3r_style", false))

	# ---- 2. Schema pass: copy every control to its spec field ----
	for key in PanelSchema.all_keys():
		var def: Dictionary = PanelSchema.get_def(key)
		if (def.type == "special"):
			continue
		var control: Control = panel._controls[key]
		var spec_field: String = def.spec_field
		if (def.type == "spin"):
			var value: float = (control as SpinBox).value
			if SPECIAL_SPIN.has(key):
				var mode: String = SPECIAL_SPIN[key]
				if mode == "int":
					value = int(value)
				elif mode == "/1000":
					value = value / 1000.0
			spec.set(spec_field, value)
		elif (def.type == "option"):
			var option: OptionButton = control as OptionButton
			var value: Variant
			if SPECIAL_OPTION.has(key):
				var mode: String = SPECIAL_OPTION[key]
				if mode == "custom":
					var twin: OptionButton = panel._controls["twin"]
					var custom_pin: SpinBox = panel._controls["custom_pin"]
					value = custom_pin.value if twin.get_item_text(twin.selected) == "Custom" else float(twin.get_item_text(twin.selected))
				elif mode == "conditional":
					var induction: String = str(panel._vehicle_settings.get("induction", "injection"))
					var stroke_type: String = panel._controls["stroke_type"].get_item_text(panel._controls["stroke_type"].selected)
					value = "velocity_stack" if option.selected == 1 and induction == "injection" and stroke_type == "four_stroke" else "stock"
				elif mode == "selected_eq_1":
					value = option.selected == 1
				elif mode == "fuel_kind":
					var idx: int = option.selected
					value = FuelTank.KINDS[idx] if idx >= 0 and idx < FuelTank.KINDS.size() else "ron95"
				else:
					value = option.get_item_text(option.selected)
			else:
				value = option.get_item_text(option.selected)
			spec.set(spec_field, value)
		elif (def.type == "toggle"):
			var toggle: ToggleSwitch = control as ToggleSwitch
			var value: Variant
			if SPECIAL_TOGGLE.has(key):
				var mode: String = SPECIAL_TOGGLE[key]
				if mode == "selected_eq_1":
					value = toggle.selected == 1
				elif mode == "wheel_aids_and_selected_eq_1":
					value = ControlPanel.WHEEL_AIDS_AVAILABLE and toggle.selected == 1
			else:
				value = toggle.selected == 1
			spec.set(spec_field, value)

	# ---- 3. Displacement (computed, not from a control) ----
	spec.displacement_cc = Units.displacement_cc(spec.bore_mm, spec.stroke_mm, spec.cylinders)

	# ---- 4. Induction from vehicle settings ----
	spec.induction = str(panel._vehicle_settings.get("induction", "injection"))

	# ---- Plain vars (not controls, set on panel by preset) ----
	spec.rod_ratio = panel.rod_ratio
	spec.compression_ratio = panel.compression_ratio
	spec.crossplane = panel.crossplane
	spec.fire_deg = panel.fire_deg
	spec.shared_v_crankpins = spec.layout == "V" and panel._controls["shared_pins"].selected == 1
	spec.vehicle_kg = panel.vehicle_kg
	spec.primary_ratio = panel.primary_ratio
	spec.final_drive = panel.final_drive
	spec.gear_ratios = panel.gear_ratios

	# Valve timing only applies to four-stroke engines
	var panel_stroke_type: String = panel._controls["stroke_type"].get_item_text(panel._controls["stroke_type"].selected)
	if panel_stroke_type == "four_stroke":
		spec.intake_duration_deg = panel._controls["in_dur"].value
		spec.intake_lift_mm = panel._controls["in_lift"].value
		spec.intake_valve_mm = panel._controls["intake_valve_mm"].value
		spec.exhaust_valve_mm = panel.exhaust_valve_mm
		spec.runner_length_m = panel._controls["runner_length_m"].value
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

	# ---- Sound levels (global, not per-build) ----
	for key in ["sound_valvetrain", "sound_mechanical", "sound_gear_whine", "sound_driveline", "sound_turbo", "sound_knock", "sound_rasp", "sound_intake"]:
		spec.set(key, panel._controls[key].value)

	# ---- Quickshifter cut profile (complex logic, not schema-driven) ----
	spec.quickshifter_cut_profile = []
	for g in range(6):
		var base = panel._controls["qs_cut_base"].value
		var profile = [[3000, base + 10], [6000, base], [10000, base - 10]]
		for p in profile:
			p[1] = p[1] * (1.0 - g * 0.05)  # shorter cut in higher gears
		spec.quickshifter_cut_profile.append(profile)

	# ---- slipper_ramp hardcoded (technical debt) ----
	spec.slipper_ramp = 0.5 # fixed for now, could add a spin box later

	# Quickshifter detailed controls (toggle and spin values not in SPECIAL_* maps)
	spec.quickshifter = panel._controls["qs_enabled"].selected == 1
	spec.quickshifter_cut_time = panel._controls["qs_cut_base"].value / 1000.0
	spec.quickshifter_blip_time = panel._controls["qs_blip_time"].value / 1000.0
	spec.quickshifter_blip_throttle = panel._controls["qs_blip_throttle"].value
	spec.quickshifter_sensitivity = panel._controls["qs_sensitivity"].value
	spec.quickshifter_flat_shift = panel._controls["qs_flat_shift"].selected == 1

	# ABS and traction control apply only when the bike has them and the wheel physics is built.
	spec.launch_control = panel._controls["launch_control"].selected == 1
	spec.abs_enabled = ControlPanel.WHEEL_AIDS_AVAILABLE and panel._controls["abs_enabled"].selected == 1
	spec.traction_control_enabled = ControlPanel.WHEEL_AIDS_AVAILABLE and panel._controls["traction_control_enabled"].selected == 1
	spec.slipper_clutch = panel._controls["slipper_clutch"].selected == 1
