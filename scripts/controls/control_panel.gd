class_name ControlPanel
extends CanvasLayer

# Left-hand panel: the engine kill switch, the engine preset, then one section at a time (engine, air and fuel, valves, timing,
# tuning), followed by validation warnings. Changes are reported through signals; main.gd applies them to the simulation.
# Each section holds one label and one value per row, so the panel does not crowd the screen.

signal changed
signal refuel_pressed
signal kill_switch_changed(killed: bool)
signal starter_changed(held: bool)
signal camera_requested(view: String)
signal dyno_pressed
signal render_pressed

const PANEL_WIDTH := 340.0 # wider and larger text for touch; the bottom-left touch pads sit beside its lower edge
const PANEL_FONT := 18 # text size on the panel, up from the default 16
const CONTROL_HEIGHT := 40.0 # minimum height of a spin box, dropdown or button, so they are easy to hit
const ACCENT := Color(0.25, 0.55, 0.9)
const BUTTON := Color(0.16, 0.17, 0.21)
const HEADING := Color(0.55, 0.75, 1.0)
const LABEL_WIDTH := 132.0
const ENGINE_LIBRARY := preload("res://scripts/engine/engine_library.gd")

var rod_ratio := 1.6 # not on screen, set by the preset
var compression_ratio := 11.3 # not on screen, set by the preset
var crossplane := false # not on screen, set by the preset
var fire_deg: Array = [] # not on screen, set by the preset: the engine's ignition wiring, so the firing matches it
var bank_angle := 90.0
var vehicle_kg := 215.0 # not on screen, set by the preset
var primary_ratio := 3.26 # gearbox values, set by the preset (defaults: K45R)
var intake_valve_mm := 20.0
var exhaust_valve_mm := 17.0
var runner_length_m := 0.25
var wall_heat_scale := 1.0
var valve_cd := 0.7
var final_drive := 3.0
var gear_ratios: Array = Gearbox.ratios()
var _vehicle_settings := {}
var _controls := {}
var _preset_button: OptionButton
var _library_ready := false
var _preset_ids: Array = []
var _preset_keys: Array = []
var _kill_button: Button
var _twin_label: Label
var _custom_pin_label: Label
var _crank_label: Label
var _bank_label: Label
var _shared_pins_label: Label
var _firing_order: LineEdit
var _firing_message: Label
var _warning: Label
var _summary: Label
var builds_path := "user://engine_builds.cfg"
var _build_name: LineEdit
var _builds: OptionButton
var _build_status: Label

func _ready() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	panel.offset_left = 16
	panel.offset_top = 16
	panel.offset_right = PANEL_WIDTH + 16
	panel.offset_bottom = -16
	panel.add_theme_stylebox_override("panel", _box(Color(0.06, 0.06, 0.08, 0.93), 6, 12))
	var theme := Theme.new()
	theme.default_font_size = PANEL_FONT
	panel.theme = theme
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	var heading := Label.new()
	heading.text = "ENGINE SETUP"
	heading.add_theme_font_size_override("font_size", PANEL_FONT - 2)
	heading.add_theme_color_override("font_color", HEADING)
	box.add_child(heading)

	# the engine kill switch, always in view: RUN lets the engine start and run, KILLED cuts the ignition
	_kill_button = Button.new()
	_kill_button.toggle_mode = true
	_kill_button.focus_mode = Control.FOCUS_NONE
	_kill_button.custom_minimum_size = Vector2(0, 52)
	_kill_button.tooltip_text = "Engine kill switch (K): RUN to start and run, KILLED to cut the ignition"
	_kill_button.toggled.connect(_on_kill_toggled)
	_style_kill(false)
	box.add_child(_kill_button)
	var starter := Button.new()
	starter.text = "HOLD TO START"
	starter.custom_minimum_size.y = CONTROL_HEIGHT
	starter.button_down.connect(func() -> void: starter_changed.emit(true))
	starter.button_up.connect(func() -> void: starter_changed.emit(false))
	_style_button(starter)
	box.add_child(starter)
	var help := Label.new()
	help.text = "W / ↑ start & throttle  ·  Shift clutch\nQ / E shift  ·  B brake  ·  Esc pause"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_font_size_override("font_size", 14)
	box.add_child(help)

	# preset dropdown - populated immediately from bundled, then refreshed when library is ready
	_preset_button = OptionButton.new()
	_preset_button.focus_mode = Control.FOCUS_NONE
	_preset_button.custom_minimum_size.y = CONTROL_HEIGHT
	_populate_preset_dropdown(Presets.PRESETS)
	_preset_button.item_selected.connect(_on_preset_selected)
	box.add_child(_preset_button)
	var reset := Button.new()
	reset.text = "Reset to selected preset"
	reset.custom_minimum_size.y = CONTROL_HEIGHT
	box.add_child(reset)
	var reset_confirm := ConfirmationDialog.new()
	reset_confirm.title = "Reset engine build?"
	reset_confirm.dialog_text = "Replace the current engine settings with the selected preset? Save your build first if you want to keep it."
	add_child(reset_confirm)
	reset.pressed.connect(func() -> void: reset_confirm.popup_centered())
	reset_confirm.confirmed.connect(func() -> void: _on_preset_selected(_preset_button.selected))
	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.add_theme_font_size_override("font_size", 15)
	box.add_child(_summary)
	var cameras := HBoxContainer.new()
	box.add_child(cameras)
	for view in ["Vehicle", "Engine"]:
		var camera_button := Button.new()
		camera_button.text = view + " view"
		camera_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		camera_button.pressed.connect(func() -> void: camera_requested.emit(view))
		cameras.add_child(camera_button)
	var build_row := HBoxContainer.new()
	box.add_child(build_row)
	_build_name = LineEdit.new()
	_build_name.placeholder_text = "Build name"
	_build_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	build_row.add_child(_build_name)
	var save_build := Button.new()
	save_build.text = "Save / overwrite"
	save_build.pressed.connect(_save_build)
	build_row.add_child(save_build)
	var load_row := HBoxContainer.new()
	box.add_child(load_row)
	_builds = OptionButton.new()
	_builds.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_row.add_child(_builds)
	var load_build := Button.new()
	load_build.text = "Load build"
	load_build.pressed.connect(_load_build)
	load_row.add_child(load_build)
	_build_status = Label.new()
	_build_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_build_status)
	_refresh_builds()

	# the dyno test runs the whole sequence by itself: start, every gear at full throttle, then the curve
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	box.add_child(actions)
	var dyno := Button.new()
	dyno.text = "Dyno test"
	dyno.focus_mode = Control.FOCUS_NONE
	dyno.custom_minimum_size = Vector2(0, CONTROL_HEIGHT + 4)
	dyno.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dyno.tooltip_text = "Starts the engine, runs every gear at full throttle, and plots torque and power. Press again to stop"
	_style_button(dyno)
	dyno.pressed.connect(func() -> void: dyno_pressed.emit())
	actions.add_child(dyno)

	# Render the exhaust sound to a WAV file at the highest simulation refresh (1/3600 physics step).
	var render_btn := Button.new()
	render_btn.text = "Render audio"
	render_btn.focus_mode = Control.FOCUS_NONE
	render_btn.custom_minimum_size = Vector2(0, CONTROL_HEIGHT + 4)
	render_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	render_btn.tooltip_text = "Renders the exhaust sound to a WAV file offline at the highest simulation refresh (1/3600 s physics step). Ignores real-time frame caps."
	_style_button(render_btn)
	render_btn.pressed.connect(func() -> void: render_pressed.emit())
	actions.add_child(render_btn)

	# Load engine library from server
	ENGINE_LIBRARY.get_instance().library_ready.connect(_on_library_ready)
	ENGINE_LIBRARY.get_instance().fetch()

	# one section at a time, picked from this dropdown: the panel stays as tall as the section it shows
		var section := OptionButton.new()
		section.custom_minimum_size.y = CONTROL_HEIGHT
		section.tooltip_text = "Engine settings section"
		for title in ["Engine", "Air and fuel", "Valves", "Timing", "Tuning", "Turbo"]:
			section.add_item(title)
		box.add_child(section)
		var pages := VBoxContainer.new()
		box.add_child(pages)
		section.item_selected.connect(func(i: int) -> void: _show_section(pages, i))

		var engine := _page(pages, "Engine")
	_controls["cyl"] = _spin(engine, "Cylinders", 1, 16, 1, 1)
	_controls["bore"] = _spin(engine, "Bore (mm)", 30, 150, 0.1, 57.3)
	_controls["stroke"] = _spin(engine, "Stroke (mm)", 20, 150, 0.1, 57.8)
	_controls["slant"] = _spin(engine, "Slant (°)", -90, 90, 1, 20)
	_controls["slant"].tooltip_text = "Cylinder lean about the crankshaft; positive leans toward the front."
	_controls["layout"] = _option(engine, "Layout", ["inline", "V", "W"])
	var bank := SpinBox.new()
	bank.min_value = 1.0
	bank.max_value = 180.0
	bank.step = 1.0
	bank.value = bank_angle
	bank.custom_minimum_size.y = CONTROL_HEIGHT
	bank.tooltip_text = "Angle between cylinder banks."
	_controls["bank_angle"] = bank
	_bank_label = _row(engine, "Bank angle (°)", bank)
	bank.value_changed.connect(func(value: float) -> void:
		bank_angle = value
		_refresh_firing_order()
		changed.emit())
	_controls["shared_pins"] = OptionButton.new()
	_controls["shared_pins"].add_item("Preset / automatic")
	_controls["shared_pins"].add_item("Shared opposite-bank pairs")
	_controls["shared_pins"].tooltip_text = "Pair cylinders 1–2, 3–4 and so on on common crankpins; firing angles adjust to the bank angle."
	_shared_pins_label = _row(engine, "Crankpins", _controls["shared_pins"])
	_controls["shared_pins"].item_selected.connect(func(_index: int) -> void:
		_refresh_firing_order()
		changed.emit())
	_controls["twin"] = OptionButton.new()
	for item in ["360", "270", "180", "Custom"]:
		_controls["twin"].add_item(item)
	_controls["twin"].item_selected.connect(_on_twin_selected)
	_controls["twin"].tooltip_text = "Crank pin angle, 2-cylinder inline only"
	_twin_label = _row(engine, "Crank pin", _controls["twin"])
	_controls["custom_pin"] = SpinBox.new()
	_controls["custom_pin"].min_value = 1.0
	_controls["custom_pin"].max_value = 359.0
	_controls["custom_pin"].step = 1.0
	_controls["custom_pin"].value = 270.0
	_custom_pin_label = _row(engine, "Custom pin (°)", _controls["custom_pin"])
	_controls["custom_pin"].value_changed.connect(func(_v: float) -> void:
		if _controls["twin"].get_item_text(_controls["twin"].selected) == "Custom":
			_on_twin_selected(_controls["twin"].selected))
	_controls["crank"] = OptionButton.new()
	_crank_label = _row(engine, "Crank", _controls["crank"])
	_controls["crank"].item_selected.connect(_on_crank_selected)
	_firing_order = LineEdit.new()
	_firing_order.placeholder_text = "e.g. 1-3-4-2"
	_firing_order.tooltip_text = "Cylinder numbers in firing order. Applying reassigns the selected firing angles to those cylinders."
	_row(engine, "Firing order", _firing_order)
	var apply_order := Button.new()
	apply_order.text = "Apply firing order"
	apply_order.pressed.connect(_apply_firing_order)
	_row(engine, "", apply_order)
	_firing_message = Label.new()
	_firing_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_row(engine, "", _firing_message)
	_controls["cyl"].value_changed.connect(func(_v: float) -> void:
		fire_deg = []
		crossplane = false
		_refresh_twin()
		changed.emit())
	_controls["layout"].item_selected.connect(func(_i: int) -> void: _refresh_twin())
	_refresh_twin()

	var air := _page(pages, "Air and fuel")
	_controls["header"] = _option(air, "Header", ["stock", "4-1", "4-2-1"])
	_controls["fuel"] = _option(air, "Fuel", FuelTank.LABELS)
	_controls["fuel"].select(FuelTank.KINDS.find("ron95")) # RON 95 is the default, as before the grades were added
	_controls["fuel"].tooltip_text = "Higher RON resists knock, so the ignition can run more advance. E85 also cools the intake charge"
	_controls["lambda"] = _spin(air, "Mixture λ", 0.6, 1.4, 0.01, 1.0)
	_controls["lambda"].tooltip_text = "1.0 = stoichiometric"
	_controls["boost_ratio"] = _spin(air, "Max boost ratio", 1.0, 3.0, 0.01, 1.0)
	_controls["boost_time"] = _spin(air, "Boost response (s)", 0.01, 5.0, 0.01, 0.6)
	_controls["compressor_battery"] = _spin(air, "Battery (Wh)", 1.0, 500.0, 1.0, 40.0)
	_controls["compressor_power"] = _spin(air, "Compressor (W)", 0.0, 10000.0, 50.0, 2000.0)
	_controls["compressor_charge"] = _spin(air, "Charging (W)", 0.0, 10000.0, 50.0, 1000.0)
	for key in ["boost_ratio", "boost_time", "compressor_battery", "compressor_power", "compressor_charge"]:
		_controls[key].tooltip_text = "Estimated value; Honda has not published the V3R compressor specifications."
	var refuel := Button.new()
	refuel.text = "Refuel"
	refuel.focus_mode = Control.FOCUS_NONE
	refuel.custom_minimum_size = Vector2(0, 40)
	_style_button(refuel)
	refuel.pressed.connect(func() -> void: refuel_pressed.emit())
	_row(air, "Tank", refuel)

	var valves := _page(pages, "Valves")
	_controls["in_dur"] = _spin(valves, "Intake duration", 150, 300, 1, 240)
	_controls["in_dur"].tooltip_text = "Crank degrees the intake valve is open"
	_controls["in_lift"] = _spin(valves, "Intake lift (mm)", 2, 15, 0.1, 6.0)
	_controls["in_centre"] = _spin(valves, "Intake centre", 360, 600, 1, 470)
	_controls["in_centre"].tooltip_text = "Where the intake event is centred, after firing top dead centre"
	_controls["ex_dur"] = _spin(valves, "Exhaust duration", 150, 300, 1, 230)
	_controls["ex_dur"].tooltip_text = "Crank degrees the exhaust valve is open"
	_controls["ex_lift"] = _spin(valves, "Exhaust lift (mm)", 2, 15, 0.1, 5.0)
	_controls["ex_centre"] = _spin(valves, "Exhaust centre", 120, 360, 1, 255)
	_controls["ex_centre"].tooltip_text = "Where the exhaust event is centred, after firing top dead centre"

	var timing_page := _page(pages, "Timing")
	_controls["timing"] = _spin(timing_page, "Timing (deg)", -10, 10, 0.5, 0)
	_controls["timing"].tooltip_text = "Advance (+) or retard (-) from the engine's timing map. Too much advance knocks; higher RON and E85 allow more"
	var timing_hint := Label.new()
	timing_hint.text = "+ advances, - retards. Past the knock limit the engine knocks."
	timing_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	timing_hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.66))
	timing_page.add_child(timing_hint)

	var tuning := _page(pages, "Tuning")
	_controls["redline"] = _spin(tuning, "Redline (rpm)", 2000, 20000, 50, 10600)
	_controls["redline"].tooltip_text = "Fuel is cut at this speed"
	_controls["idle"] = _spin(tuning, "Idle speed (rpm)", 400, 6000, 10, 1200)
	_controls["idle"].tooltip_text = "The rpm the ECU holds at idle with the throttle closed, like the idle screw on a real bike"
	_controls["flywheel"] = _spin(tuning, "Flywheel (kg)", 0.5, 10.0, 0.01, 2.5)
	_controls["flywheel_r"] = _spin(tuning, "Flywheel radius (mm)", 20, 150, 0.1, 75.0)
	_controls["power_mode"] = _option(tuning, "Power mode", ["F", "M", "L"])
	_controls["power_mode"].tooltip_text = "F = Full power, M = Mid (softer), L = Low (rain/eco). Changes throttle response and ignition timing."
	_controls["quickshifter"] = OptionButton.new()
	_controls["quickshifter"].add_item("Off")
	_controls["quickshifter"].add_item("On")
	_controls["quickshifter"].tooltip_text = "Quickshifter: clutchless upshift with ignition/fuel cut (SE models)"
	_row(tuning, "Quickshifter", _controls["quickshifter"])
	_controls["launch_control"] = OptionButton.new()
	_controls["launch_control"].add_item("Off")
	_controls["launch_control"].add_item("On")
	_controls["launch_control"].tooltip_text = "Launch control: holds RPM at launch_rpm while clutch pulled + throttle > 95% (SE models)"
	_row(tuning, "Launch control", _controls["launch_control"])
	_controls["slipper_clutch"] = OptionButton.new()
	_controls["slipper_clutch"].add_item("Off")
	_controls["slipper_clutch"].add_item("On")
	_controls["slipper_clutch"].tooltip_text = "Slipper clutch: reduces clutch capacity during engine braking to prevent rear wheel hop"
	_row(tuning, "Slipper clutch", _controls["slipper_clutch"])

		var turbo := _page(pages, "Turbo")
		var map_view = CompressorMapView.new()
		map_view.custom_minimum_size = Vector2(300, 300)
		turbo.add_child(map_view)
		_controls["compressor_map_view"] = map_view

		_warning = Label.new()
	_warning.modulate = Color(1.0, 0.7, 0.3)
	_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_warning)



# Copies the panel's values into the engine spec.
func apply_to(spec: EngineSpec) -> void:
	var layout: OptionButton = _controls["layout"]
	var header: OptionButton = _controls["header"]
	var fuel: OptionButton = _controls["fuel"]
	spec.cylinders = int(_controls["cyl"].value)
	spec.bore_mm = _controls["bore"].value
	spec.stroke_mm = _controls["stroke"].value
	spec.slant_deg = _controls["slant"].value
	# displacement is not an input: it follows from bore, stroke and cylinder count
	spec.displacement_cc = Units.displacement_cc(spec.bore_mm, spec.stroke_mm, spec.cylinders)
	spec.layout = layout.get_item_text(layout.selected)
	var twin: OptionButton = _controls["twin"]
	spec.twin_pin_deg = _controls["custom_pin"].value if twin.get_item_text(twin.selected) == "Custom" else float(twin.get_item_text(twin.selected))
	spec.header = header.get_item_text(header.selected)
	spec.fuel = FuelTank.KINDS[fuel.selected]
	spec.rod_ratio = rod_ratio
	spec.compression_ratio = compression_ratio
	spec.crossplane = crossplane
	spec.fire_deg = fire_deg
	spec.bank_angle = _controls["bank_angle"].value
	spec.shared_v_crankpins = spec.layout == "V" and _controls["shared_pins"].selected == 1
	spec.vehicle_kg = vehicle_kg
	spec.primary_ratio = primary_ratio
	spec.final_drive = final_drive
	spec.gear_ratios = gear_ratios
	var default_spec := EngineSpec.new()
	for key in ["vehicle_type", "transmission_type", "wheelbase_mm", "wheel_radius_m", "vehicle_length_mm", "vehicle_width_mm", "vehicle_height_mm", "front_track_mm", "rear_track_mm", "front_wheel_radius_m", "front_tire_width_mm", "rear_tire_width_mm", "fuel_capacity_l", "drag_area_m2", "max_boost_ratio", "electric_compressor", "boost_spool_time", "intake_area_scale", "manifold_volume_scale", "clutch_capacity_nm"]:
		spec.set(key, _vehicle_settings.get(key, default_spec.get(key)))
	spec.v3r_style = bool(_vehicle_settings.get("v3r_style", false))
	spec.max_boost_ratio = _controls["boost_ratio"].value
	spec.boost_spool_time = _controls["boost_time"].value
	spec.compressor_battery_wh = _controls["compressor_battery"].value
	spec.compressor_power_w = _controls["compressor_power"].value
	spec.compressor_charge_w = _controls["compressor_charge"].value
	spec.redline_rpm = _controls["redline"].value
	spec.flywheel_kg = _controls["flywheel"].value
	spec.flywheel_radius_mm = _controls["flywheel_r"].value
	spec.intake_duration_deg = _controls["in_dur"].value
	spec.intake_lift_mm = _controls["in_lift"].value
	spec.intake_valve_mm = intake_valve_mm
	spec.exhaust_valve_mm = exhaust_valve_mm
	spec.runner_length_m = runner_length_m
	spec.wall_heat_scale = wall_heat_scale
	spec.valve_cd = valve_cd
	spec.intake_centre_deg = _controls["in_centre"].value
	spec.exhaust_duration_deg = _controls["ex_dur"].value
	spec.exhaust_lift_mm = _controls["ex_lift"].value
	spec.exhaust_centre_deg = _controls["ex_centre"].value
	spec.ignition_offset_deg = _controls["timing"].value
	spec.idle_target_rpm = _controls["idle"].value
	spec.cam_lobe_profile = int(_vehicle_settings.get("cam_lobe_profile", spec.cam_lobe_profile))
	spec.intake_lobe_profile = int(_vehicle_settings.get("intake_lobe_profile", spec.cam_lobe_profile))
	spec.exhaust_lobe_profile = int(_vehicle_settings.get("exhaust_lobe_profile", spec.cam_lobe_profile))
	spec.intake_open_ramp_deg = float(_vehicle_settings.get("intake_open_ramp_deg", 0.0))
	spec.intake_close_ramp_deg = float(_vehicle_settings.get("intake_close_ramp_deg", 0.0))
	spec.exhaust_open_ramp_deg = float(_vehicle_settings.get("exhaust_open_ramp_deg", 0.0))
	spec.exhaust_close_ramp_deg = float(_vehicle_settings.get("exhaust_close_ramp_deg", 0.0))
	spec.intake_duration_050_deg = float(_vehicle_settings.get("intake_duration_050_deg", 0.0))
	spec.exhaust_duration_050_deg = float(_vehicle_settings.get("exhaust_duration_050_deg", 0.0))
	spec.intake_lift_curve = _vehicle_settings.get("intake_lift_curve", [])
	spec.exhaust_lift_curve = _vehicle_settings.get("exhaust_lift_curve", [])
	# New ZX-25R features
	spec.power_mode = _controls["power_mode"].get_item_text(_controls["power_mode"].selected)
	spec.quickshifter = _controls["quickshifter"].selected == 1
	spec.launch_control = _controls["launch_control"].selected == 1
	spec.slipper_clutch = _controls["slipper_clutch"].selected == 1
	spec.slipper_ramp = 0.5 # fixed for now, could add a spin box later


func lambda() -> float:
	return _controls["lambda"].value


func set_warning(text: String) -> void:
	_warning.text = text


func set_build_summary(spec: EngineSpec) -> void:
	_summary.text = "%.1f cc · %s · %d cyl\n%.1f × %.1f mm · %.1f:1" % [spec.displacement_cc, spec.layout, spec.cylinders, spec.bore_mm, spec.stroke_mm, spec.compression_ratio]


func _refresh_builds(selected := "") -> void:
	var config := ConfigFile.new()
	config.load(builds_path)
	_builds.clear()
	var names := config.get_sections()
	names.sort()
	for build_name in names:
		_builds.add_item(build_name)
	if not selected.is_empty() and names.has(selected):
		_builds.select(names.find(selected))
	_builds.disabled = names.is_empty()


func _save_build() -> void:
	var build_name := _build_name.text.strip_edges()
	if build_name.is_empty() or build_name.contains("]") or build_name.contains("[") or build_name.contains("\n"):
		_build_status.text = "Enter a build name without brackets."
		return
	var values := {}
	for key in _controls:
		var control: Control = _controls[key]
		if control is SpinBox:
			values[key] = control.value
		elif control is OptionButton:
			values[key] = control.get_item_text(control.selected)
	var config := ConfigFile.new()
	config.load(builds_path)
	config.set_value(build_name, "controls", values)
	config.set_value(build_name, "preset_data", _vehicle_settings)
	config.set_value(build_name, "preset_id", _preset_ids[_preset_button.selected] if _preset_button.selected >= 0 else "")
	for key in ["rod_ratio", "compression_ratio", "crossplane", "fire_deg", "bank_angle", "vehicle_kg", "primary_ratio", "intake_valve_mm", "exhaust_valve_mm", "runner_length_m", "wall_heat_scale", "valve_cd", "final_drive", "gear_ratios"]:
		config.set_value(build_name, key, get(key))
	var err := config.save(builds_path)
	_build_status.text = "Saved: " + build_name if err == OK else "Could not save build (error %d)." % err
	if err == OK:
		_refresh_builds(build_name)


func _load_build() -> void:
	if _builds.selected < 0:
		return
	var build_name := _builds.get_item_text(_builds.selected)
	var config := ConfigFile.new()
	if config.load(builds_path) != OK:
		_build_status.text = "Could not load builds."
		return
	var values: Variant = config.get_value(build_name, "controls", {})
	var preset_data: Variant = config.get_value(build_name, "preset_data", {})
	if not values is Dictionary or not preset_data is Dictionary:
		_build_status.text = "Build data is invalid."
		return
	_vehicle_settings = preset_data
	for key in ["rod_ratio", "compression_ratio", "crossplane", "fire_deg", "bank_angle", "vehicle_kg", "primary_ratio", "intake_valve_mm", "exhaust_valve_mm", "runner_length_m", "wall_heat_scale", "valve_cd", "final_drive", "gear_ratios"]:
		var value: Variant = config.get_value(build_name, key, get(key))
		if typeof(value) == typeof(get(key)):
			set(key, value)
	_set_quiet(_controls["bank_angle"], bank_angle)
	_controls["shared_pins"].select(0)
	for key in _controls:
		if not values.has(key):
			continue
		if key == "crank":
			_refresh_twin()
		var control: Control = _controls[key]
		if control is SpinBox and (values[key] is float or values[key] is int):
			_set_quiet(control, values[key])
		elif control is OptionButton and values[key] is String:
			_select_text(control, values[key])
	bank_angle = _controls["bank_angle"].value
	var preset_index := _preset_ids.find(str(config.get_value(build_name, "preset_id", "")))
	if preset_index >= 0:
		_preset_button.select(preset_index)
	_refresh_twin()
	_build_name.text = build_name
	_build_status.text = "Loaded: " + build_name
	changed.emit()


func _refresh_twin() -> void:
	var layout: OptionButton = _controls["layout"]
	var count := int(_controls["cyl"].value)
	var inline := layout.get_item_text(layout.selected) == "inline"
	_bank_label.visible = not inline
	_controls["bank_angle"].visible = not inline
	_shared_pins_label.visible = layout.get_item_text(layout.selected) == "V" and count >= 2
	_controls["shared_pins"].visible = _shared_pins_label.visible
	var twin_applies := count == 2 and inline
	_twin_label.visible = twin_applies
	_controls["twin"].visible = twin_applies
	_custom_pin_label.visible = twin_applies and _controls["twin"].get_item_text(_controls["twin"].selected) == "Custom"
	_controls["custom_pin"].visible = _custom_pin_label.visible
	var crank: OptionButton = _controls["crank"]
	var old := crank.get_item_text(crank.selected) if crank.selected >= 0 else ""
	var options: Array = ["Preset / current"]
	if inline and count == 3:
		options.append_array(["Even 120°", "T-plane 180°/270°/270°"])
	elif inline and count == 4:
		options.append_array(["Flat-plane", "Crossplane"])
	if crank.item_count != options.size() or (crank.item_count > 1 and crank.get_item_text(1) != options[1]):
		crank.clear()
		for option in options:
			crank.add_item(option)
		_select_text(crank, old)
	_crank_label.visible = inline and count in [3, 4]
	crank.visible = _crank_label.visible
	_refresh_firing_order()


func _current_fire_angles() -> Array:
	var count := int(_controls["cyl"].value)
	var twin: OptionButton = _controls["twin"]
	var text := twin.get_item_text(twin.selected)
	var pin: float = _controls["custom_pin"].value if text == "Custom" else float(text)
	var spec := EngineSpec.new()
	spec.cylinders = count
	spec.fire_deg = fire_deg
	spec.twin_pin_deg = pin
	spec.crossplane = crossplane
	spec.layout = _controls["layout"].get_item_text(_controls["layout"].selected)
	spec.bank_angle = _controls["bank_angle"].value
	spec.shared_v_crankpins = _controls["shared_pins"].selected == 1
	spec.v3r_style = bool(_vehicle_settings.get("v3r_style", false))
	return Array(FiringOrders.for_spec(spec))


func _refresh_firing_order() -> void:
	var angles := _current_fire_angles()
	var ordered := []
	for i in angles.size():
		ordered.append([float(angles[i]), i + 1])
	ordered.sort_custom(func(a, b): return a[0] < b[0])
	var labels := PackedStringArray()
	for entry in ordered:
		labels.append(str(entry[1]))
	_firing_order.text = "-".join(labels)
	_firing_message.text = "Shared pairs adjust firing angles to match the bank angle." if _shared_pins_label.visible and _controls["shared_pins"].selected == 1 else "Order reassigns firing angles and crank pins to cylinders."


func _on_twin_selected(_index: int) -> void:
	var text: String = _controls["twin"].get_item_text(_controls["twin"].selected)
	var angle: float = _controls["custom_pin"].value if text == "Custom" else float(text)
	fire_deg = [0.0, angle]
	_refresh_twin()
	changed.emit()


func _on_crank_selected(index: int) -> void:
	if index == 0:
		return
	var count := int(_controls["cyl"].value)
	crossplane = count == 4 and index == 2
	if count == 3:
		fire_deg = [0.0, 240.0, 480.0] if index == 1 else [0.0, 180.0, 450.0]
	else:
		fire_deg = Array(FiringOrders.fire_angles(4, 360.0, crossplane))
	_refresh_firing_order()
	changed.emit()


func _apply_firing_order() -> void:
	var parts := _firing_order.text.replace(",", "-").replace(" ", "").split("-", false)
	var angles := _current_fire_angles()
	if parts.size() != angles.size():
		_firing_message.text = "Enter each cylinder number once."
		return
	var order := []
	for part in parts:
		if not part.is_valid_int() or int(part) < 1 or int(part) > angles.size() or order.has(int(part)):
			_firing_message.text = "Enter each cylinder number once."
			return
		order.append(int(part))
	angles.sort()
	for i in range(1, angles.size()):
		if is_equal_approx(float(angles[i]), float(angles[i - 1])):
			_firing_message.text = "Simultaneous firing angles cannot be reordered here."
			return
	fire_deg.resize(angles.size())
	for i in order.size():
		fire_deg[order[i] - 1] = angles[i]
	_refresh_firing_order()
	_firing_message.text = "Applied; shared crankpin geometry may adjust the order." if _shared_pins_label.visible and _controls["shared_pins"].selected == 1 else "Applied. Cylinder crank pins follow the new order."
	changed.emit()


# Flips the kill switch, as the K key does.
func toggle_kill() -> void:
	_kill_button.button_pressed = not _kill_button.button_pressed


func _populate_preset_dropdown(library: Dictionary) -> void:
	var keys := library.keys()
	if keys == _preset_keys:
		return
	_preset_keys = keys
	_preset_button.clear()
	_preset_ids = []
	var seen_names := {}
	for id in keys:
		var preset: Dictionary = library[id]
		var display_name := str(preset.get("display_name", id))
		if seen_names.has(display_name):
			continue
		seen_names[display_name] = true
		_preset_ids.append(id)
		_preset_button.add_item(display_name)
	_preset_button.disabled = _preset_button.get_item_count() == 0
	# Select CBR150R as default
	if _preset_button.get_item_count() > 0:
		var pick := _preset_ids.find("honda_cbr150r")
		if pick < 0:
			pick = 0
		_preset_button.select(pick)


func _on_library_ready(library: Dictionary) -> void:
	_library_ready = true
	_populate_preset_dropdown(library)


func _on_kill_toggled(killed: bool) -> void:
	_style_kill(killed)
	kill_switch_changed.emit(killed)


# Green RUN when the engine may run, red KILLED when the ignition is cut.
func _style_kill(killed: bool) -> void:
	_kill_button.text = "IGNITION: OFF  (K)" if killed else "IGNITION: RUN  (K)"
	var fill := Color(0.72, 0.13, 0.13) if killed else Color(0.13, 0.46, 0.22)
	for state in ["normal", "pressed", "hover", "focus"]:
		_kill_button.add_theme_stylebox_override(state, _box(fill.lightened(0.1) if state == "hover" else fill, 8, 8))


func _on_preset_selected(index: int) -> void:
	if index >= _preset_ids.size():
		return
	var id: String = _preset_ids[index]
	var library: Dictionary = ENGINE_LIBRARY.get_instance().get_library()
	if library.is_empty() or not library.has(id):
		return
	var p: Dictionary = library[id]
	_vehicle_settings = p
	_preset_button.tooltip_text = str(p.get("display_name", id))
	_set_quiet(_controls["cyl"], p.cylinders)
	_set_quiet(_controls["bore"], p.bore_mm)
	_set_quiet(_controls["stroke"], p.stroke_mm)
	_set_quiet(_controls["slant"], p.get("slant_deg", 20.0))
	_select_text(_controls["layout"], p.layout)
	_select_text(_controls["header"], p.header)
	_controls["fuel"].select(FuelTank.KINDS.find(p.fuel))
	var pin := float(p.get("twin_pin_deg", 360.0))
	if pin in [180.0, 270.0, 360.0]:
		_select_text(_controls["twin"], str(int(pin)))
	else:
		_set_quiet(_controls["custom_pin"], pin)
		_select_text(_controls["twin"], "Custom")
	_set_quiet(_controls["boost_ratio"], p.get("max_boost_ratio", 1.0))
	_set_quiet(_controls["boost_time"], p.get("boost_spool_time", 0.6))
	_set_quiet(_controls["compressor_battery"], p.get("compressor_battery_wh", 40.0))
	_set_quiet(_controls["compressor_power"], p.get("compressor_power_w", 2000.0))
	_set_quiet(_controls["compressor_charge"], p.get("compressor_charge_w", 1000.0))
	_set_quiet(_controls["redline"], p.redline_rpm)
	_set_quiet(_controls["flywheel"], p.flywheel_kg)
	_set_quiet(_controls["flywheel_r"], p.flywheel_radius_mm)
	# the cams and timing go back to the stock values (or the preset's own) when a preset is picked
	_set_quiet(_controls["in_dur"], p.get("intake_duration_deg", 240.0))
	_set_quiet(_controls["in_lift"], p.get("intake_lift_mm", 6.0))
	_set_quiet(_controls["in_centre"], p.get("intake_centre_deg", 470.0))
	_set_quiet(_controls["ex_dur"], p.get("exhaust_duration_deg", 230.0))
	_set_quiet(_controls["ex_lift"], p.get("exhaust_lift_mm", 5.0))
	_set_quiet(_controls["ex_centre"], p.get("exhaust_centre_deg", 255.0))
	_set_quiet(_controls["timing"], 0.0)
	_set_quiet(_controls["idle"], p.get("idle_target_rpm", 1200.0))
	rod_ratio = p.rod_ratio
	compression_ratio = p.get("compression_ratio", 11.3)
	crossplane = p.get("crossplane", false)
	fire_deg = p.get("fire_deg", [])
	_controls["crank"].select(0)
	bank_angle = p.get("bank_angle", 90.0)
	_set_quiet(_controls["bank_angle"], bank_angle)
	_controls["shared_pins"].select(1 if p.get("shared_v_crankpins", false) else 0)
	vehicle_kg = p.get("vehicle_kg", 215.0)
	# gearbox: K45R values unless the preset gives its own
	primary_ratio = p.get("primary_ratio", 3.26)
	intake_valve_mm = p.get("intake_valve_mm", 20.0)
	exhaust_valve_mm = p.get("exhaust_valve_mm", 17.0)
	runner_length_m = p.get("runner_length_m", 0.25)
	wall_heat_scale = p.get("wall_heat_scale", 1.0)
	valve_cd = p.get("valve_cd", 0.7)
	final_drive = p.get("final_drive", 3.0)
	gear_ratios = p.get("gear_ratios", Gearbox.ratios())
	# New ZX-25R features
	_select_text(_controls["power_mode"], p.get("power_mode", "F"))
	_controls["quickshifter"].select(1 if p.get("quickshifter", false) else 0)
	_controls["launch_control"].select(1 if p.get("launch_control", false) else 0)
	_controls["slipper_clutch"].select(1 if p.get("slipper_clutch", false) else 0)
	_refresh_twin() # set_quiet does not signal, so update the crank-pin row here
	changed.emit()


# One section: a column that holds its own grid. The first one is shown; the dropdown switches the others in.
func _page(host: Control, title: String) -> GridContainer:
	var page := VBoxContainer.new()
	page.name = title
	page.visible = host.get_child_count() == 0
	page.add_theme_constant_override("separation", 8)
	host.add_child(page)
	return _grid(page)


func _show_section(pages: Control, index: int) -> void:
	for i in pages.get_child_count():
		pages.get_child(i).visible = i == index


func _grid(box: Control) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)
	return grid


# One row: the label on the left, its control filling the right.
func _row(grid: GridContainer, text: String, control: Control) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = LABEL_WIDTH # same width in every section, so the values line up
	grid.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(control)
	return label


func _spin(grid: GridContainer, label: String, lo: float, hi: float, step: float, value: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size.y = CONTROL_HEIGHT
	s.value_changed.connect(func(_v: float) -> void: changed.emit())
	_row(grid, label, s)
	return s


func _option(grid: GridContainer, label: String, items: Array) -> OptionButton:
	var o := OptionButton.new()
	for item in items:
		o.add_item(item)
	o.custom_minimum_size.y = CONTROL_HEIGHT
	o.item_selected.connect(func(_i: int) -> void: changed.emit())
	_row(grid, label, o)
	return o


# Buttons are tall and wide enough to hit with a thumb on a phone.
func _button(text: String, parent: Control) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, CONTROL_HEIGHT + 12)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(b)
	parent.add_child(b)
	return b


func _style_button(b: Button) -> void:
	b.add_theme_stylebox_override("normal", _box(BUTTON, 8, 8))
	b.add_theme_stylebox_override("hover", _box(BUTTON.lightened(0.12), 8, 8))
	b.add_theme_stylebox_override("pressed", _box(ACCENT, 8, 8)) # lit while held, or while Sound is on



# A rounded box used for the panel, the readouts and the buttons.
func _box(fill: Color, radius: int, margin: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	return s


# Sets a SpinBox without firing value_changed, so a preset causes one rebuild, not one per field.
func _set_quiet(box: SpinBox, value: float) -> void:
	box.set_block_signals(true)
	box.value = value
	box.set_block_signals(false)


func _select_text(option: OptionButton, text: String) -> void:
	for i in option.item_count:
		if option.get_item_text(i) == text:
			option.select(i)
