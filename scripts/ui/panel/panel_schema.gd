class_name PanelSchema
extends RefCounted

# PanelSchema: single source of truth for every control in the control panel.
#
# Each entry describes one on-screen control: its label, type, defaults, ranges,
# the EngineSpec field it writes to, the preset key it reads from, and the
# category page it lives on. All four panel files (control_panel.gd,
# panel_presets.gd, panel_spec.gd, panel_builds.gd) iterate over this dictionary
# instead of duplicating control<->spec mapping by hand.
#
# Adding a control means editing ONLY this file plus any special-case logic in
# control_panel.gd (e.g. firing order, twin pin). The preset loader, spec
# applicator, and build serializer all follow automatically.

# Categories in tab order.
const CATEGORIES: Array[String] = [
	"Engine",
	"Intake and fuel",
	"Exhaust",
	"Valvetrain",
	"Ignition",
	"Forced induction",
	"Rider aids",
	"Vehicle",
	"Sound",
]

# Short tab labels shown on the buttons.
const CATEGORY_TABS: Array[String] = [
	"Engine",
	"Intake",
	"Exhaust",
	"Valves",
	"Ignition",
	"Boost",
	"Aids",
	"Vehicle",
	"Sound",
]

# Values the preset sets that are not on screen.
const PLAIN_VARS: Array[String] = [
	"rod_ratio",
	"compression_ratio",
	"crossplane",
	"fire_deg",
	"bank_angle",
	"vehicle_kg",
	"primary_ratio",
	"exhaust_valve_mm",
	"wall_heat_scale",
	"valve_cd",
	"final_drive",
	"gear_ratios",
]

# Controls on each page: a category reset puts exactly these back to the preset's values.
const CATEGORY_KEYS := {
	"Engine": [
		"cyl", "bore", "stroke", "slant", "layout", "stroke_type",
		"bank_angle", "shared_pins", "twin", "custom_pin", "crank",
	],
	"Intake and fuel": [
		"intake_valve_mm", "runner_length_m", "fuel", "lambda",
		"intake_display", "stack_length",
	],
	"Exhaust": [
		"header", "muffler_style", "live_exhaust_physics",
	],
	"Valvetrain": [
		"in_dur", "in_lift", "in_centre", "ex_dur", "ex_lift", "ex_centre",
	],
	"Ignition": [
		"timing", "idle", "power_mode",
	],
	"Forced induction": [
		"boost_ratio", "boost_time", "compressor_battery", "compressor_power", "compressor_charge",
	],
	"Rider aids": [
		"qs_enabled", "qs_sensitivity", "qs_cut_base", "qs_blip_time",
		"qs_blip_throttle", "qs_flat_shift", "launch_control", "slipper_clutch",
	],
	"Vehicle": [
		"redline", "flywheel", "flywheel_r", "speed_limit_enabled", "speed_limit_kmh",
	],
	"Sound": [
		"sound_valvetrain", "sound_mechanical", "sound_gear_whine", "sound_driveline",
		"sound_turbo", "sound_knock", "sound_rasp", "sound_intake",
	],
}

# Every control definition. Keys match _controls entries in ControlPanel.
#
# Common fields:
#   label      - display label
#   type       - "spin", "option", "toggle", "line_edit", "special"
#   category   - which CATEGORY_KEYS page it belongs to
#   tooltip    - hover help text
#
# Spin fields: min, max, step, default, unit, spec_field, preset_key
# Option fields: items, default_index, spec_field, preset_key
# Toggle fields: default, spec_field, preset_key
const CONTROLS := {
	# ---------- Engine page ----------
	"cyl": {
		"label": "Cylinders",
		"type": "spin",
		"category": "Engine",
		"min": 1.0, "max": 16.0, "step": 1.0, "default": 1.0,
		"unit": "",
		"spec_field": "cylinders",
		"preset_key": "cylinders",
		"tooltip": "Number of cylinders.",
	},
	"bore": {
		"label": "Bore (mm)",
		"type": "spin",
		"category": "Engine",
		"min": 30.0, "max": 150.0, "step": 0.1, "default": 57.3,
		"unit": "mm",
		"spec_field": "bore_mm",
		"preset_key": "bore_mm",
		"tooltip": "Cylinder bore diameter.",
	},
	"stroke": {
		"label": "Stroke (mm)",
		"type": "spin",
		"category": "Engine",
		"min": 20.0, "max": 150.0, "step": 0.1, "default": 57.8,
		"unit": "mm",
		"spec_field": "stroke_mm",
		"preset_key": "stroke_mm",
		"tooltip": "Cylinder stroke.",
	},
	"slant": {
		"label": "Slant (°)",
		"type": "spin",
		"category": "Engine",
		"min": -90.0, "max": 90.0, "step": 1.0, "default": 20.0,
		"unit": "°",
		"spec_field": "slant_deg",
		"preset_key": "slant_deg",
		"tooltip": "Cylinder lean about the crankshaft; positive leans toward the front.",
	},
	"layout": {
		"label": "Layout",
		"type": "option",
		"category": "Engine",
		"items": ["inline", "V", "W"],
		"default_index": 0,
		"spec_field": "layout",
		"preset_key": "layout",
		"tooltip": "Cylinder arrangement.",
	},
	"stroke_type": {
		"label": "Stroke type",
		"type": "option",
		"category": "Engine",
		"items": ["four_stroke", "two_stroke"],
		"default_index": 0,
		"spec_field": "stroke_type",
		"preset_key": "stroke_type",
		"tooltip": "Four-stroke: valves, 720° cycle. Two-stroke: ports, 360° cycle, expansion chamber.",
	},
	"bank_angle": {
		"label": "Bank angle (°)",
		"type": "spin",
		"category": "Engine",
		"min": 1.0, "max": 180.0, "step": 1.0, "default": 90.0,
		"unit": "°",
		"spec_field": "bank_angle",
		"preset_key": "bank_angle",
		"tooltip": "Angle between cylinder banks.",
	},
	"shared_pins": {
		"label": "Crankpins",
		"type": "option",
		"category": "Engine",
		"items": ["Preset / automatic", "Shared opposite-bank pairs"],
		"default_index": 0,
		"spec_field": "shared_v_crankpins",
		"preset_key": "shared_v_crankpins",
		"tooltip": "Pair cylinders 1-2, 3-4 and so on on common crankpins; firing angles adjust to the bank angle.",
	},
	"twin": {
		"label": "Crank pin",
		"type": "option",
		"category": "Engine",
		"items": ["360", "270", "180", "Custom"],
		"default_index": 0,
		"spec_field": "twin_pin_deg",
		"preset_key": "twin_pin_deg",
		"tooltip": "Crank pin angle, 2-cylinder inline only.",
	},
	"custom_pin": {
		"label": "Custom pin (°)",
		"type": "spin",
		"category": "Engine",
		"min": 1.0, "max": 359.0, "step": 1.0, "default": 270.0,
		"unit": "°",
		"spec_field": "twin_pin_deg",
		"preset_key": "twin_pin_deg",
		"tooltip": "Custom crank pin angle when Crank pin is set to Custom.",
	},
	"crank": {
		"label": "Crank",
		"type": "special",
		"category": "Engine",
		"tooltip": "Crank firing configuration.",
	},
	"firing_order": {
		"label": "Firing order",
		"type": "special",
		"category": "Engine",
		"tooltip": "Cylinder numbers in firing order. Applying reassigns the selected firing angles to those cylinders.",
	},

	# ---------- Intake and fuel page ----------
	"intake_valve_mm": {
		"label": "Intake valve (mm)",
		"type": "spin",
		"category": "Intake and fuel",
		"min": 10.0, "max": 60.0, "step": 0.5, "default": 20.0,
		"unit": "mm",
		"spec_field": "intake_valve_mm",
		"preset_key": "intake_valve_mm",
		"tooltip": "Intake valve head diameter. Sets the largest flow area. Four-stroke only.",
	},
	"runner_length_m": {
		"label": "Runner (m)",
		"type": "spin",
		"category": "Intake and fuel",
		"min": 0.05, "max": 1.0, "step": 0.01, "default": 0.25,
		"unit": "m",
		"spec_field": "runner_length_m",
		"preset_key": "runner_length_m",
		"tooltip": "Throttle body to valve. A shorter runner holds its fill to a higher rpm. Four-stroke only.",
	},
	"intake_display": {
		"label": "Intake appearance",
		"type": "option",
		"category": "Intake and fuel",
		"items": ["Stock", "Velocity stack"],
		"default_index": 0,
		"spec_field": "intake_display",
		"preset_key": "intake_display",
		"tooltip": "Draws the velocity stacks. Appearance only: airflow physics does not change.",
	},
	"stack_length": {
		"label": "Stack length (mm)",
		"type": "spin",
		"category": "Intake and fuel",
		"min": 10.0, "max": 200.0, "step": 1.0, "default": 70.0,
		"unit": "mm",
		"spec_field": "velocity_stack_length_mm",
		"preset_key": "velocity_stack_length_mm",
		"tooltip": "Drawn length of the velocity stack. Not a factory dimension.",
	},
	"fuel": {
		"label": "Fuel",
		"type": "option",
		"category": "Intake and fuel",
		"items": [],
		"default_index": 0,
		"spec_field": "fuel",
		"preset_key": "fuel",
		"tooltip": "Higher RON resists knock, so the ignition can run more advance.",
	},
	"lambda": {
		"label": "Mixture λ",
		"type": "spin",
		"category": "Intake and fuel",
		"min": 0.6, "max": 1.4, "step": 0.01, "default": 1.0,
		"unit": "",
		"spec_field": "lambda_target",
		"preset_key": "lambda_target",
		"tooltip": "1.0 = stoichiometric",
	},

	# ---------- Valvetrain page ----------
	"in_dur": {
		"label": "Intake duration",
		"type": "spin",
		"category": "Valvetrain",
		"min": 150.0, "max": 300.0, "step": 0.5, "default": 240.0,
		"unit": "°",
		"spec_field": "intake_duration_deg",
		"preset_key": "intake_duration_deg",
		"tooltip": "Crank degrees the intake valve is open.",
	},
	"in_lift": {
		"label": "Intake lift (mm)",
		"type": "spin",
		"category": "Valvetrain",
		"min": 2.0, "max": 15.0, "step": 0.1, "default": 6.0,
		"unit": "mm",
		"spec_field": "intake_lift_mm",
		"preset_key": "intake_lift_mm",
		"tooltip": "Intake valve lift.",
	},
	"in_centre": {
		"label": "Intake centre",
		"type": "spin",
		"category": "Valvetrain",
		"min": 360.0, "max": 600.0, "step": 1.0, "default": 470.0,
		"unit": "°",
		"spec_field": "intake_centre_deg",
		"preset_key": "intake_centre_deg",
		"tooltip": "Where the intake event is centred, after firing top dead centre.",
	},
	"ex_dur": {
		"label": "Exhaust duration",
		"type": "spin",
		"category": "Valvetrain",
		"min": 150.0, "max": 300.0, "step": 0.5, "default": 230.0,
		"unit": "°",
		"spec_field": "exhaust_duration_deg",
		"preset_key": "exhaust_duration_deg",
		"tooltip": "Crank degrees the exhaust valve is open.",
	},
	"ex_lift": {
		"label": "Exhaust lift (mm)",
		"type": "spin",
		"category": "Valvetrain",
		"min": 2.0, "max": 15.0, "step": 0.1, "default": 5.0,
		"unit": "mm",
		"spec_field": "exhaust_lift_mm",
		"preset_key": "exhaust_lift_mm",
		"tooltip": "Exhaust valve lift.",
	},
	"ex_centre": {
		"label": "Exhaust centre",
		"type": "spin",
		"category": "Valvetrain",
		"min": 120.0, "max": 360.0, "step": 1.0, "default": 255.0,
		"unit": "°",
		"spec_field": "exhaust_centre_deg",
		"preset_key": "exhaust_centre_deg",
		"tooltip": "Where the exhaust event is centred, after firing top dead centre.",
	},

	# ---------- Ignition page ----------
	"timing": {
		"label": "Timing (deg)",
		"type": "spin",
		"category": "Ignition",
		"min": -10.0, "max": 10.0, "step": 0.5, "default": 0.0,
		"unit": "°",
		"spec_field": "ignition_offset_deg",
		"preset_key": "ignition_offset_deg",
		"tooltip": "Advance (+) or retard (-) from the engine's timing map.",
	},
	"idle": {
		"label": "Idle speed (rpm)",
		"type": "spin",
		"category": "Ignition",
		"min": 400.0, "max": 6000.0, "step": 10.0, "default": 1200.0,
		"unit": "rpm",
		"spec_field": "idle_target_rpm",
		"preset_key": "idle_target_rpm",
		"tooltip": "The rpm the ECU holds at idle with the throttle closed.",
	},
	"power_mode": {
		"label": "Power mode",
		"type": "option",
		"category": "Ignition",
		"items": ["F", "M", "L"],
		"default_index": 0,
		"spec_field": "power_mode",
		"preset_key": "power_mode",
		"tooltip": "F = Full power, M = Mid (softer), L = Low (rain/eco).",
	},

	# ---------- Forced induction page ----------
	"boost_ratio": {
		"label": "Max boost ratio",
		"type": "spin",
		"category": "Forced induction",
		"min": 1.0, "max": 3.0, "step": 0.01, "default": 1.0,
		"unit": "",
		"spec_field": "max_boost_ratio",
		"preset_key": "max_boost_ratio",
		"tooltip": "Estimated value; Honda has not published the V3R compressor specifications.",
	},
	"boost_time": {
		"label": "Boost response (s)",
		"type": "spin",
		"category": "Forced induction",
		"min": 0.01, "max": 5.0, "step": 0.01, "default": 0.6,
		"unit": "s",
		"spec_field": "boost_spool_time",
		"preset_key": "boost_spool_time",
		"tooltip": "Estimated value; Honda has not published the V3R compressor specifications.",
	},
	"compressor_battery": {
		"label": "Battery (Wh)",
		"type": "spin",
		"category": "Forced induction",
		"min": 1.0, "max": 500.0, "step": 1.0, "default": 40.0,
		"unit": "Wh",
		"spec_field": "compressor_battery_wh",
		"preset_key": "compressor_battery_wh",
		"tooltip": "Estimated value; Honda has not published the V3R compressor specifications.",
	},
	"compressor_power": {
		"label": "Compressor (W)",
		"type": "spin",
		"category": "Forced induction",
		"min": 0.0, "max": 10000.0, "step": 50.0, "default": 2000.0,
		"unit": "W",
		"spec_field": "compressor_power_w",
		"preset_key": "compressor_power_w",
		"tooltip": "Estimated value; Honda has not published the V3R compressor specifications.",
	},
	"compressor_charge": {
		"label": "Charging (W)",
		"type": "spin",
		"category": "Forced induction",
		"min": 0.0, "max": 10000.0, "step": 50.0, "default": 1000.0,
		"unit": "W",
		"spec_field": "compressor_charge_w",
		"preset_key": "compressor_charge_w",
		"tooltip": "Estimated value; Honda has not published the V3R compressor specifications.",
	},

	# ---------- Rider aids page ----------
	"qs_enabled": {
		"label": "Quickshifter",
		"type": "toggle",
		"category": "Rider aids",
		"default": false,
		"spec_field": "quickshifter",
		"preset_key": "quickshifter",
		"tooltip": "Enable clutchless upshift with ignition/fuel cut.",
	},
	"qs_sensitivity": {
		"label": "Shift force",
		"type": "spin",
		"category": "Rider aids",
		"min": 0.1, "max": 1.0, "step": 0.05, "default": 0.7,
		"unit": "",
		"spec_field": "quickshifter_sensitivity",
		"preset_key": "quickshifter_sensitivity",
		"tooltip": "How firm a press the shifter needs before it shifts.",
	},
	"qs_cut_base": {
		"label": "Base Cut (ms)",
		"type": "spin",
		"category": "Rider aids",
		"min": 20.0, "max": 100.0, "step": 5.0, "default": 50.0,
		"unit": "ms",
		"spec_field": "quickshifter_cut_time",
		"preset_key": "quickshifter_cut_time",
		"tooltip": "Base ignition cut duration at low RPM.",
	},
	"qs_blip_time": {
		"label": "Downshift Blip (ms)",
		"type": "spin",
		"category": "Rider aids",
		"min": 20.0, "max": 200.0, "step": 10.0, "default": 80.0,
		"unit": "ms",
		"spec_field": "quickshifter_blip_time",
		"preset_key": "quickshifter_blip_time",
		"tooltip": "Throttle blip duration for clutchless downshift.",
	},
	"qs_blip_throttle": {
		"label": "Blip Throttle %",
		"type": "spin",
		"category": "Rider aids",
		"min": 0.1, "max": 0.5, "step": 0.05, "default": 0.3,
		"unit": "",
		"spec_field": "quickshifter_blip_throttle",
		"preset_key": "quickshifter_blip_throttle",
		"tooltip": "Throttle fraction during downshift blip.",
	},
	"qs_flat_shift": {
		"label": "Flat Shift",
		"type": "toggle",
		"category": "Rider aids",
		"default": false,
		"spec_field": "quickshifter_flat_shift",
		"preset_key": "quickshifter_flat_shift",
		"tooltip": "Hold throttle cracked during upshift for faster shifts.",
	},
	"launch_control": {
		"label": "Launch control",
		"type": "toggle",
		"category": "Rider aids",
		"default": false,
		"spec_field": "launch_control",
		"preset_key": "launch_control",
		"tooltip": "Holds launch RPM while the clutch is pulled and throttle is high.",
	},
	"slipper_clutch": {
		"label": "Slipper clutch",
		"type": "toggle",
		"category": "Rider aids",
		"default": false,
		"spec_field": "slipper_clutch",
		"preset_key": "slipper_clutch",
		"tooltip": "Slipper clutch: reduces clutch capacity during engine braking.",
	},
	"abs_enabled": {
		"label": "ABS",
		"type": "toggle",
		"category": "Rider aids",
		"default": false,
		"spec_field": "abs_enabled",
		"preset_key": "abs_enabled",
		"tooltip": "Anti-lock braking system. Not built yet; switch is locked.",
		"visible_when": "wheel_aids_available",
	},
	"traction_control_enabled": {
		"label": "Traction control",
		"type": "toggle",
		"category": "Rider aids",
		"default": false,
		"spec_field": "traction_control_enabled",
		"preset_key": "traction_control_enabled",
		"tooltip": "Traction control. Not built yet; switch is locked.",
		"visible_when": "wheel_aids_available",
	},

	# ---------- Vehicle page ----------
	"redline": {
		"label": "Redline (rpm)",
		"type": "spin",
		"category": "Vehicle",
		"min": 2000.0, "max": 25000.0, "step": 50.0, "default": 10600.0,
		"unit": "rpm",
		"spec_field": "redline_rpm",
		"preset_key": "redline_rpm",
		"tooltip": "Fuel cut rpm. Torque drops to zero above this.",
	},
	"flywheel": {
		"label": "Flywheel (kg)",
		"type": "spin",
		"category": "Vehicle",
		"min": 0.1, "max": 50.0, "step": 0.01, "default": 2.5,
		"unit": "kg",
		"spec_field": "flywheel_kg",
		"preset_key": "flywheel_kg",
		"tooltip": "Flywheel mass in kg.",
	},
	"flywheel_r": {
		"label": "Flywheel radius (mm)",
		"type": "spin",
		"category": "Vehicle",
		"min": 10.0, "max": 300.0, "step": 0.1, "default": 75.0,
		"unit": "mm",
		"spec_field": "flywheel_radius_mm",
		"preset_key": "flywheel_radius_mm",
		"tooltip": "Radius at which the flywheel mass acts.",
	},
	"speed_limit_enabled": {
		"label": "Speed limit",
		"type": "toggle",
		"category": "Vehicle",
		"default": false,
		"spec_field": "speed_limit_enabled",
		"preset_key": "speed_limit_enabled",
		"tooltip": "Enable electronic speed limiter.",
	},
	"speed_limit_kmh": {
		"label": "Limit (km/h)",
		"type": "spin",
		"category": "Vehicle",
		"min": 50.0, "max": 400.0, "step": 1.0, "default": 300.0,
		"unit": "km/h",
		"spec_field": "speed_limit_kmh",
		"preset_key": "speed_limit_kmh",
		"tooltip": "Speed limiter threshold.",
	},

	# ---------- Exhaust page ----------
	"header": {
		"label": "Header",
		"type": "option",
		"category": "Exhaust",
		"items": ["stock", "4-1", "4-2-1"],
		"default_index": 0,
		"spec_field": "header",
		"preset_key": "header",
		"tooltip": "Exhaust header layout.",
	},
	"muffler_style": {
		"label": "Muffler",
		"type": "option",
		"category": "Exhaust",
		"items": ["stock", "sport", "short"],
		"default_index": 0,
		"spec_field": "muffler_style",
		"preset_key": "muffler_style",
		"tooltip": "Estimated four-stroke muffler shapes and lengths; two-stroke expansion chambers are unchanged.",
	},
	"live_exhaust_physics": {
		"label": "Exhaust physics",
		"type": "option",
		"category": "Exhaust",
		"items": ["Off", "Experimental"],
		"default_index": 0,
		"spec_field": "live_exhaust_physics",
		"preset_key": "live_exhaust_physics",
		"tooltip": "Experimental live pressure-wave solver; changes torque and uses more CPU.",
	},

	# ---------- Sound page ----------
	"sound_valvetrain": {
		"label": "Valvetrain",
		"type": "spin",
		"category": "Sound",
		"min": 0.0, "max": 1.0, "step": 0.01, "default": 0.4,
		"unit": "",
		"spec_field": "snd_valvetrain",
		"preset_key": "snd_valvetrain",
		"tooltip": "Cam/valve gear whine volume.",
	},
	"sound_mechanical": {
		"label": "Mechanical",
		"type": "spin",
		"category": "Sound",
		"min": 0.0, "max": 1.0, "step": 0.01, "default": 0.5,
		"unit": "",
		"spec_field": "snd_mechanical",
		"preset_key": "snd_mechanical",
		"tooltip": "Crank/rod/piston mechanical noise.",
	},
	"sound_gear_whine": {
		"label": "Gear whine",
		"type": "spin",
		"category": "Sound",
		"min": 0.0, "max": 1.0, "step": 0.01, "default": 0.3,
		"unit": "",
		"spec_field": "snd_gear_whine",
		"preset_key": "snd_gear_whine",
		"tooltip": "Straight-cut gear whine volume.",
	},
	"sound_driveline": {
		"label": "Driveline",
		"type": "spin",
		"category": "Sound",
		"min": 0.0, "max": 1.0, "step": 0.01, "default": 0.2,
		"unit": "",
		"spec_field": "snd_driveline",
		"preset_key": "snd_driveline",
		"tooltip": "Chain/shaft drone.",
	},
	"sound_turbo": {
		"label": "Turbo",
		"type": "spin",
		"category": "Sound",
		"min": 0.0, "max": 1.0, "step": 0.01, "default": 0.3,
		"unit": "",
		"spec_field": "snd_turbo",
		"preset_key": "snd_turbo",
		"tooltip": "Compressor whine and wastegate.",
	},
	"sound_knock": {
		"label": "Knock",
		"type": "spin",
		"category": "Sound",
		"min": 0.0, "max": 1.0, "step": 0.01, "default": 0.2,
		"unit": "",
		"spec_field": "snd_knock",
		"preset_key": "snd_knock",
		"tooltip": "Detonation ping volume.",
	},
	"sound_rasp": {
		"label": "Rasp",
		"type": "spin",
		"category": "Sound",
		"min": 0.0, "max": 1.0, "step": 0.01, "default": 0.2,
		"unit": "",
		"spec_field": "snd_rasp",
		"preset_key": "snd_rasp",
		"tooltip": "Exhaust rasp/crackle on overrun.",
	},
	"sound_intake": {
		"label": "Intake",
		"type": "spin",
		"category": "Sound",
		"min": 0.0, "max": 1.0, "step": 0.01, "default": 0.15,
		"unit": "",
		"spec_field": "snd_intake",
		"preset_key": "snd_intake",
		"tooltip": "Intake roar / velocity stack hiss.",
	},
}

# Fuel labels come from FuelTank at runtime; the option is filled by set_fuel_items.
static var _fuel_items: Array = []

static func set_fuel_items(items: Array) -> void:
	_fuel_items = items.duplicate()

static func get_fuel_items() -> Array:
	return _fuel_items.duplicate()

# Look up a control definition by key.
static func get_def(key: String) -> Dictionary:
	if CONTROLS.has(key):
		return CONTROLS[key]
	push_error("PanelSchema: unknown key: " + key)
	return {}

# Check if a control key exists.
static func has(key: String) -> bool:
	return CONTROLS.has(key)

# True when a control only shows under a condition (e.g. wheel aids).
static func is_visible_conditional(key: String) -> bool:
	return CONTROLS.has(key) and CONTROLS[key].has("visible_when")

static func visible_condition(key: String) -> String:
	return str(CONTROLS.get(key, {}).get("visible_when", ""))

# All control keys.
static func all_keys() -> Array[String]:
	var keys: Array[String] = []
	keys.assign(CONTROLS.keys())
	return keys

# Keys belonging to a category.
static func get_category_keys(category: String) -> Array[String]:
	var keys: Array[String] = []
	if CATEGORY_KEYS.has(category):
		keys.assign(CATEGORY_KEYS[category])
	return keys

# Plain vars that the preset restores but are not on screen.
static func get_plain_vars() -> Array[String]:
	return PLAIN_VARS

# Category list in tab order.
static func get_categories() -> Array[String]:
	return CATEGORIES

# Short tab labels.
static func get_category_tabs() -> Array[String]:
	return CATEGORY_TABS
