class_name ControlPanel
extends CanvasLayer
const WHEEL_AIDS_AVAILABLE := false # ABS/TC await independent wheel-slip physics

# Left-hand panel: the engine kill switch, the engine preset, then one section at a time (engine, air and fuel, valves, timing,
# tuning), followed by validation warnings. Changes are reported through signals; main.gd applies them to the simulation.
# Each section holds one label and one value per row, so the panel does not crowd the screen.

signal changed
signal refuel_pressed
signal kill_switch_changed(killed: bool)
signal starter_changed(held: bool)
signal camera_requested(view: String)
signal engine_cover_changed(assembled: bool)
signal dyno_pressed
signal render_pressed

const PANEL_WIDTH := 340.0 # wider and larger text for touch; the bottom-left touch pads sit beside its lower edge
const PANEL_FONT := 18 # text size on the panel, up from the default 16
const CONTROL_HEIGHT := 40.0 # minimum height of a spin box, dropdown or button, so they are easy to hit
const ACCENT := Color(0.25, 0.55, 0.9)
const BUTTON := Color(0.16, 0.17, 0.21)
const HEADING := Color(0.55, 0.75, 1.0)
const LABEL_WIDTH := 132.0
const ENGINE_LIBRARY := preload("res://scripts/presets/engine_library.gd")

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
var _feature_labels := {}
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
var _firing_rows: Array[Control] = [] # the firing-order rows: only a multi-cylinder engine has a firing order
var _warning: Label
var builds_path := "user://engine_builds.cfg"
var _build_name: LineEdit
var _builds: OptionButton
var _build_status: Label

# The seven categories, in the order of the tabs. Forced induction and Rider aids are shown only for bikes that have them.
const CATEGORIES := ["Engine", "Intake and fuel", "Valvetrain", "Ignition", "Forced induction", "Rider aids", "Vehicle"]
const CATEGORY_TABS := ["Engine", "Intake", "Valves", "Ignition", "Boost", "Aids", "Vehicle"]
# The controls on each page: a category reset puts exactly these back to the preset's values.
const CATEGORY_KEYS := {
	"Engine": ["cyl", "bore", "stroke", "slant", "layout", "stroke_type", "bank_angle", "shared_pins", "twin", "custom_pin", "crank"],
	"Intake and fuel": ["header", "muffler_style", "live_exhaust_physics", "fuel", "lambda", "intake_display", "stack_length"],
	"Valvetrain": ["in_dur", "in_lift", "in_centre", "ex_dur", "ex_lift", "ex_centre"],
	"Ignition": ["timing", "idle", "power_mode"],
	"Forced induction": ["boost_ratio", "boost_time", "compressor_battery", "compressor_power", "compressor_charge"],
	"Rider aids": ["qs_enabled", "qs_sensitivity", "qs_cut_base", "qs_blip_time", "qs_blip_throttle", "qs_flat_shift", "launch_control", "slipper_clutch"],
	"Vehicle": ["redline", "flywheel", "flywheel_r", "speed_limit_enabled", "speed_limit_kmh"],
}
# Values the preset sets that are not on screen: another category's reset must not touch them.
const PLAIN_VARS := ["rod_ratio", "compression_ratio", "crossplane", "fire_deg", "bank_angle", "vehicle_kg", "primary_ratio", "intake_valve_mm", "exhaust_valve_mm", "runner_length_m", "wall_heat_scale", "valve_cd", "final_drive", "gear_ratios"]
var _tabs: Array[Button] = []
var _pages_root: VBoxContainer
var _category := 0

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
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	panel.add_child(root)
	# the fixed top: the rider controls, the preset, the actions and the category tabs. Only the page below them scrolls.
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	root.add_child(box)
	var heading := Label.new()
	heading.text = "ENGINE SETUP"
	heading.add_theme_font_size_override("font_size", PANEL_FONT - 2)
	heading.add_theme_color_override("font_color", HEADING)
	box.add_child(heading)

	# the engine kill switch and the starter, side by side and always in view
	var rider := HBoxContainer.new()
	rider.add_theme_constant_override("separation", 8)
	box.add_child(rider)
	_kill_button = Button.new()
	_kill_button.toggle_mode = true
	_kill_button.focus_mode = Control.FOCUS_NONE
	_kill_button.custom_minimum_size = Vector2(0, 52)
	_kill_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_kill_button.tooltip_text = "Engine kill switch (K): RUN to start and run, KILLED to cut the ignition"
	_kill_button.toggled.connect(_on_kill_toggled)
	_style_kill(false)
	rider.add_child(_kill_button)
	var starter := Button.new()
	starter.text = "HOLD TO START"
	starter.custom_minimum_size = Vector2(0, 52)
	starter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	starter.button_down.connect(func() -> void: starter_changed.emit(true))
	starter.button_up.connect(func() -> void: starter_changed.emit(false))
	_style_button(starter)
	rider.add_child(starter)

	# preset dropdown, populated immediately from the bundled presets, then refreshed when the library is ready
	_preset_button = OptionButton.new()
	_preset_button.focus_mode = Control.FOCUS_NONE
	_preset_button.custom_minimum_size.y = CONTROL_HEIGHT
	_populate_preset_dropdown(Presets.PRESETS)
	_preset_button.item_selected.connect(_on_preset_selected)
	box.add_child(_preset_button)

	# the action bar: the dyno test runs the whole sequence by itself, the render writes the exhaust sound to a WAV file at the
	# highest simulation refresh, and Reset puts the whole bike back to the preset
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	box.add_child(actions)
	var dyno := Button.new()
	dyno.text = "Dyno"
	dyno.focus_mode = Control.FOCUS_NONE
	dyno.custom_minimum_size = Vector2(0, CONTROL_HEIGHT)
	dyno.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dyno.tooltip_text = "Starts the engine, runs every gear at full throttle, and plots torque and power. Press again to stop"
	_style_button(dyno)
	dyno.pressed.connect(func() -> void: dyno_pressed.emit())
	actions.add_child(dyno)
	var render_btn := Button.new()
	render_btn.text = "Render"
	render_btn.focus_mode = Control.FOCUS_NONE
	render_btn.custom_minimum_size = Vector2(0, CONTROL_HEIGHT)
	render_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	render_btn.tooltip_text = "Renders the exhaust sound to a WAV file offline at the highest simulation refresh (1/3600 s physics step). Ignores real-time frame caps."
	_style_button(render_btn)
	render_btn.pressed.connect(func() -> void: render_pressed.emit())
	actions.add_child(render_btn)

	# views, and the builds drawer: save and load a build by name
	var views := HBoxContainer.new()
	views.add_theme_constant_override("separation", 6)
	box.add_child(views)
	for view in ["Vehicle", "Engine"]:
		var camera_button := Button.new()
		camera_button.text = view + " view"
		camera_button.focus_mode = Control.FOCUS_NONE
		camera_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		camera_button.pressed.connect(func() -> void: camera_requested.emit(view))
		views.add_child(camera_button)
	var covers := Button.new()
	covers.text = "Show engine covers"
	covers.toggle_mode = true
	covers.focus_mode = Control.FOCUS_NONE
	covers.custom_minimum_size.y = CONTROL_HEIGHT
	covers.toggled.connect(func(assembled: bool) -> void:
		covers.text = "Inspect engine internals" if assembled else "Show engine covers"
		engine_cover_changed.emit(assembled))
	box.add_child(covers)
	var builds_toggle := Button.new()
	builds_toggle.text = "Builds"
	builds_toggle.toggle_mode = true
	builds_toggle.focus_mode = Control.FOCUS_NONE
	builds_toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	builds_toggle.tooltip_text = "Save and load builds"
	views.add_child(builds_toggle)
	var builds_box := VBoxContainer.new()
	builds_box.visible = false
	box.add_child(builds_box)
	builds_toggle.toggled.connect(func(on: bool) -> void: builds_box.visible = on)
	var build_row := HBoxContainer.new()
	builds_box.add_child(build_row)
	_build_name = LineEdit.new()
	_build_name.placeholder_text = "Build name"
	_build_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	build_row.add_child(_build_name)
	var save_build := Button.new()
	save_build.text = "Save"
	save_build.pressed.connect(_save_build)
	build_row.add_child(save_build)
	var load_row := HBoxContainer.new()
	builds_box.add_child(load_row)
	_builds = OptionButton.new()
	_builds.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_row.add_child(_builds)
	var load_build := Button.new()
	load_build.text = "Load"
	load_build.pressed.connect(_load_build)
	load_row.add_child(load_build)
	_build_status = Label.new()
	_build_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	builds_box.add_child(_build_status)
	_refresh_builds()

	# load the engine library from the server
	ENGINE_LIBRARY.get_instance().library_ready.connect(_on_library_ready)
	ENGINE_LIBRARY.get_instance().fetch()

	# the category tabs: one page at a time, so the panel is as tall as the page it shows
	var tab_grid := GridContainer.new()
	tab_grid.columns = 4
	tab_grid.add_theme_constant_override("h_separation", 4)
	tab_grid.add_theme_constant_override("v_separation", 4)
	box.add_child(tab_grid)
	var tab_group := ButtonGroup.new()
	for i in CATEGORIES.size():
		var tab := Button.new()
		tab.text = CATEGORY_TABS[i]
		tab.toggle_mode = true
		tab.button_group = tab_group
		tab.focus_mode = Control.FOCUS_NONE
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.custom_minimum_size.y = 36
		tab.add_theme_font_size_override("font_size", 14)
		tab.tooltip_text = CATEGORIES[i]
		tab.pressed.connect(func() -> void: _select_category(i))
		_style_button(tab)
		tab_grid.add_child(tab)
		_tabs.append(tab)
	_tabs[0].button_pressed = true

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	root.add_child(scroll)
	var pages_box := VBoxContainer.new()
	pages_box.add_theme_constant_override("separation", 8)
	pages_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pages_box)
	var pages := VBoxContainer.new()
	pages_box.add_child(pages)
	_pages_root = pages
	# the seven pages, in the order of the tabs
	var engine := _page(pages, "Engine")
	var air := _page(pages, "Intake and fuel")
	var valves := _page(pages, "Valvetrain")
	var timing_page := _page(pages, "Ignition")
	var boost := _page(pages, "Forced induction")
	var aids := _page(pages, "Rider aids")
	var vehicle := _page(pages, "Vehicle")
	_controls["cyl"] = _spin(engine, "Cylinders", 1, 16, 1, 1)
	_controls["bore"] = _spin(engine, "Bore (mm)", 30, 150, 0.1, 57.3)
	_controls["stroke"] = _spin(engine, "Stroke (mm)", 20, 150, 0.1, 57.8)
	_controls["slant"] = _spin(engine, "Slant (°)", -90, 90, 1, 20)
	_controls["slant"].tooltip_text = "Cylinder lean about the crankshaft; positive leans toward the front."
	_controls["layout"] = _option(engine, "Layout", ["inline", "V", "W"])
	_controls["stroke_type"] = _option(engine, "Stroke type", ["four_stroke", "two_stroke"])
	_controls["stroke_type"].tooltip_text = "Four-stroke: valves, 720° cycle. Two-stroke: ports, 360° cycle, expansion chamber."
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
	_firing_rows.append(_row(engine, "Firing order", _firing_order))
	_firing_rows.append(_firing_order)
	var apply_order := Button.new()
	apply_order.text = "Apply firing order"
	apply_order.pressed.connect(_apply_firing_order)
	_firing_rows.append(_row(engine, "", apply_order))
	_firing_rows.append(apply_order)
	_firing_message = Label.new()
	_firing_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_firing_rows.append(_row(engine, "", _firing_message))
	_firing_rows.append(_firing_message)
	_controls["cyl"].value_changed.connect(func(_v: float) -> void:
		fire_deg = []
		crossplane = false
		_refresh_twin()
		changed.emit())
	_controls["layout"].item_selected.connect(func(_i: int) -> void: _refresh_twin())
	_refresh_twin()

	_controls["header"] = _option(air, "Header", ["stock", "4-1", "4-2-1"])
	_controls["muffler_style"] = _option(air, "Muffler", ["stock", "sport", "short"])
	_controls["muffler_style"].tooltip_text = "Estimated four-stroke muffler shapes and lengths; two-stroke expansion chambers are unchanged."
	_controls["live_exhaust_physics"] = _option(air, "Exhaust physics", ["Off", "Experimental"])
	_controls["live_exhaust_physics"].tooltip_text = "Experimental live pressure-wave solver; changes torque and uses more CPU. Not yet calibrated to a real exhaust."
	var exhaust_note := Label.new()
	exhaust_note.text = "Experimental: affects torque; uses more CPU"
	exhaust_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_row(air, "", exhaust_note)
	_controls["intake_display"] = _option(air, "Intake appearance", ["Stock", "Velocity stack"])
	_controls["intake_display"].tooltip_text = "Visual only: stock intake dimensions are estimated; airflow physics is unchanged."
	_controls["stack_length"] = _spin(air, "Stack length (mm)", 10.0, 200.0, 1.0, 70.0)
	_controls["stack_length"].tooltip_text = "Aftermarket stack visual length; not a verified factory dimension and does not change engine physics."
	var intake_note := Label.new()
	intake_note.text = "Visual only · four-stroke fuel injection"
	intake_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_row(air, "", intake_note)
	_controls["fuel"] = _option(air, "Fuel", FuelTank.LABELS)
	_controls["fuel"].select(FuelTank.KINDS.find("ron95")) # RON 95 is the default, as before the grades were added
	_controls["fuel"].tooltip_text = "Higher RON resists knock, so the ignition can run more advance. E85 also cools the intake charge"
	_controls["lambda"] = _spin(air, "Mixture λ", 0.6, 1.4, 0.01, 1.0)
	_controls["lambda"].tooltip_text = "1.0 = stoichiometric"
	_controls["boost_ratio"] = _spin(boost, "Max boost ratio", 1.0, 3.0, 0.01, 1.0)
	_controls["boost_time"] = _spin(boost, "Boost response (s)", 0.01, 5.0, 0.01, 0.6)
	_controls["compressor_battery"] = _spin(boost, "Battery (Wh)", 1.0, 500.0, 1.0, 40.0)
	_controls["compressor_power"] = _spin(boost, "Compressor (W)", 0.0, 10000.0, 50.0, 2000.0)
	_controls["compressor_charge"] = _spin(boost, "Charging (W)", 0.0, 10000.0, 50.0, 1000.0)
	for key in ["boost_ratio", "boost_time", "compressor_battery", "compressor_power", "compressor_charge"]:
		_controls[key].tooltip_text = "Estimated value; Honda has not published the V3R compressor specifications."
	var refuel := Button.new()
	refuel.text = "Refuel"
	refuel.focus_mode = Control.FOCUS_NONE
	refuel.custom_minimum_size = Vector2(0, 40)
	_style_button(refuel)
	refuel.pressed.connect(func() -> void: refuel_pressed.emit())
	_row(air, "Tank", refuel)

	_controls["in_dur"] = _spin(valves, "Intake duration", 150, 300, 0.5, 240)
	_controls["in_dur"].tooltip_text = "Crank degrees the intake valve is open"
	_controls["in_lift"] = _spin(valves, "Intake lift (mm)", 2, 15, 0.1, 6.0)
	_controls["in_centre"] = _spin(valves, "Intake centre", 360, 600, 1, 470)
	_controls["in_centre"].tooltip_text = "Where the intake event is centred, after firing top dead centre"
	_controls["ex_dur"] = _spin(valves, "Exhaust duration", 150, 300, 0.5, 230)
	_controls["ex_dur"].tooltip_text = "Crank degrees the exhaust valve is open"
	_controls["ex_lift"] = _spin(valves, "Exhaust lift (mm)", 2, 15, 0.1, 5.0)
	_controls["ex_centre"] = _spin(valves, "Exhaust centre", 120, 360, 1, 255)
	_controls["ex_centre"].tooltip_text = "Where the exhaust event is centred, after firing top dead centre"

	_controls["timing"] = _spin(timing_page, "Timing (deg)", -10, 10, 0.5, 0)
	_controls["timing"].tooltip_text = "Advance (+) or retard (-) from the engine's timing map. Too much advance knocks; higher RON and E85 allow more"
	var timing_hint := Label.new()
	timing_hint.text = "+ advances, - retards. Past the knock limit the engine knocks."
	timing_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	timing_hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.66))
	timing_page.add_child(timing_hint)

	_controls["redline"] = _spin(vehicle, "Redline (rpm)", 2000, 20000, 50, 10600)
	_controls["redline"].tooltip_text = "Fuel is cut at this speed"
	_controls["speed_limit_enabled"] = _option(vehicle, "Speed limiter", ["Off", "On"])
	_controls["speed_limit_enabled"].tooltip_text = "The voluntary 300 km/h limit most makers fit. On: the ECU closes the throttle at the limit and the bike holds it"
	_controls["speed_limit_kmh"] = _spin(vehicle, "Speed limit (km/h)", 100, 400, 1, 300)
	_controls["speed_limit_kmh"].tooltip_text = "The speed the limiter holds, km/h"
	_controls["idle"] = _spin(timing_page, "Idle speed (rpm)", 400, 6000, 10, 1200)
	_controls["idle"].tooltip_text = "The rpm the ECU holds at idle with the throttle closed, like the idle screw on a real bike"
	_controls["flywheel"] = _spin(vehicle, "Flywheel (kg)", 0.5, 10.0, 0.01, 2.5)
	_controls["flywheel_r"] = _spin(vehicle, "Flywheel radius (mm)", 20, 150, 0.1, 75.0)
	_controls["power_mode"] = _option(timing_page, "Power mode", ["F", "M", "L"])
	_controls["power_mode"].tooltip_text = "F = Full power, M = Mid (softer), L = Low (rain/eco). Changes throttle response and ignition timing."

	# Quickshifter detailed controls (only visible when has_quickshifter)
	_controls["qs_enabled"] = _option(aids, "Quickshifter", ["Off", "On"])
	_controls["qs_enabled"].tooltip_text = "Enable clutchless upshift with ignition/fuel cut"
	_feature_labels["qs_enabled"] = _label_of(_controls["qs_enabled"])
	_controls["qs_sensitivity"] = _spin(aids, "Shift force", 0.1, 1.0, 0.05, 0.7)
	_controls["qs_sensitivity"].tooltip_text = "How firm a press the shifter needs before it shifts: higher needs a firmer press. Keys press fully, so this shows with an analogue shifter"
	_feature_labels["qs_sensitivity"] = _label_of(_controls["qs_sensitivity"])
	_controls["qs_cut_base"] = _spin(aids, "Base Cut (ms)", 20, 100, 5, 50)
	_controls["qs_cut_base"].tooltip_text = "Base ignition cut duration at low RPM"
	_feature_labels["qs_cut_base"] = _label_of(_controls["qs_cut_base"])
	_controls["qs_blip_time"] = _spin(aids, "Downshift Blip (ms)", 20, 200, 10, 80)
	_controls["qs_blip_time"].tooltip_text = "Throttle blip duration for clutchless downshift"
	_feature_labels["qs_blip_time"] = _label_of(_controls["qs_blip_time"])
	_controls["qs_blip_throttle"] = _spin(aids, "Blip Throttle %", 0.1, 0.5, 0.05, 0.3)
	_controls["qs_blip_throttle"].tooltip_text = "Throttle fraction during downshift blip"
	_feature_labels["qs_blip_throttle"] = _label_of(_controls["qs_blip_throttle"])
	_controls["qs_flat_shift"] = _option(aids, "Flat Shift", ["Off", "On"])
	_controls["qs_flat_shift"].tooltip_text = "Hold throttle cracked during upshift for faster shifts"
	_feature_labels["qs_flat_shift"] = _label_of(_controls["qs_flat_shift"])

	_feature_switch(aids, "launch_control", "Launch control", "Holds launch RPM while the clutch is pulled and throttle is high.")
	_feature_switch(aids, "abs_enabled", "ABS", "Anti-lock braking system. Intervention is available when wheel-brake simulation is active.")
	_feature_switch(aids, "traction_control_enabled", "Traction control", "Traction control. Intervention is available when tyre-slip simulation is active.")
	_controls["slipper_clutch"] = OptionButton.new()
	_controls["slipper_clutch"].add_item("Off")
	_controls["slipper_clutch"].add_item("On")
	_controls["slipper_clutch"].tooltip_text = "Slipper clutch: reduces clutch capacity during engine braking to prevent rear wheel hop"
	_row(aids, "Slipper clutch", _controls["slipper_clutch"])

	var map_view = CompressorMapView.new()
	map_view.custom_minimum_size = Vector2(300, 300)
	boost.add_child(map_view)
	_controls["compressor_map_view"] = map_view

	# a reset on each page: just that category goes back to the preset
	for i in CATEGORIES.size():
		var page: Control = _pages_root.get_child(i)
		var reset_page := Button.new()
		reset_page.text = "Reset %s" % CATEGORIES[i].to_lower()
		reset_page.focus_mode = Control.FOCUS_NONE
		reset_page.custom_minimum_size.y = CONTROL_HEIGHT
		reset_page.tooltip_text = "Put only the %s settings back to the selected preset" % CATEGORIES[i].to_lower()
		_style_button(reset_page)
		reset_page.pressed.connect(func() -> void: _reset_category(i))
		page.add_child(reset_page)

	_warning = Label.new()
	_warning.modulate = Color(1.0, 0.7, 0.3)
	_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pages_box.add_child(_warning)
	var help := Label.new()
	help.text = "W / ↑ start & throttle  ·  Shift clutch\nQ / E shift  ·  B brake  ·  Esc pause"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_font_size_override("font_size", 14)
	pages_box.add_child(help)



func lambda() -> float:
	return _controls["lambda"].value


func set_warning(text: String) -> void:
	_warning.text = text


func _refresh_twin() -> void:
	var layout: OptionButton = _controls["layout"]
	var count := int(_controls["cyl"].value)
	for node in _firing_rows:
		node.visible = count > 1
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


func _feature_switch(grid: GridContainer, key: String, label_text: String, tooltip: String) -> void:
	var option := OptionButton.new()
	option.add_item("Off")
	option.add_item("On")
	option.custom_minimum_size.y = CONTROL_HEIGHT
	option.tooltip_text = tooltip
	option.item_selected.connect(func(_index: int) -> void: changed.emit())
	_controls[key] = option
	_feature_labels[key] = _row(grid, label_text, option)


func _refresh_feature_switches() -> void:
	var fitted := {
		"qs_enabled": bool(_vehicle_settings.get("has_quickshifter", false)),
		"launch_control": bool(_vehicle_settings.get("has_launch_control", false)),
		"abs_enabled": bool(_vehicle_settings.get("has_abs", false)),
		"traction_control_enabled": bool(_vehicle_settings.get("has_traction_control", false)),
	}
	fitted["abs_enabled"] = fitted["abs_enabled"] and WHEEL_AIDS_AVAILABLE
	fitted["traction_control_enabled"] = fitted["traction_control_enabled"] and WHEEL_AIDS_AVAILABLE
	for key in fitted:
		var shown: bool = fitted[key]
		_controls[key].visible = shown
		_feature_labels[key].visible = shown
		if not shown:
			_controls[key].select(0)
	
	# Quickshifter detailed controls visibility
	var qs_visible: bool = fitted["qs_enabled"]
	_controls["qs_enabled"].visible = qs_visible
	_controls["qs_sensitivity"].visible = qs_visible
	_controls["qs_cut_base"].visible = qs_visible
	_controls["qs_blip_time"].visible = qs_visible
	_controls["qs_blip_throttle"].visible = qs_visible
	_controls["qs_flat_shift"].visible = qs_visible
	# Also hide their labels
	if _feature_labels.has("qs_enabled"):
		_feature_labels["qs_enabled"].visible = qs_visible
	if _feature_labels.has("qs_sensitivity"):
		_feature_labels["qs_sensitivity"].visible = qs_visible
	if _feature_labels.has("qs_cut_base"):
		_feature_labels["qs_cut_base"].visible = qs_visible
	if _feature_labels.has("qs_blip_time"):
		_feature_labels["qs_blip_time"].visible = qs_visible
	if _feature_labels.has("qs_blip_throttle"):
		_feature_labels["qs_blip_throttle"].visible = qs_visible
	if _feature_labels.has("qs_flat_shift"):
		_feature_labels["qs_flat_shift"].visible = qs_visible
	_refresh_categories()


# Shows one category's page and presses its tab.
func _select_category(index: int) -> void:
	_category = index
	if _pages_root != null:
		_show_section(_pages_root, index)
	if index < _tabs.size():
		_tabs[index].button_pressed = true


# Forced induction shows for a bike with a compressor or a turbo; Rider aids for a bike with a quickshifter, launch control or a
# slipper clutch. Other bikes do not see an empty page.
func _refresh_categories() -> void:
	if _tabs.size() < CATEGORIES.size():
		return
	var boosted := float(_vehicle_settings.get("max_boost_ratio", 1.0)) > 1.0 or bool(_vehicle_settings.get("electric_compressor", false)) or str(_vehicle_settings.get("compressor_map_id", "")) != ""
	var aided := bool(_vehicle_settings.get("has_quickshifter", false)) or bool(_vehicle_settings.get("has_launch_control", false)) or bool(_vehicle_settings.get("slipper_clutch", false))
	_tabs[4].visible = boosted
	_tabs[5].visible = aided
	if not _tabs[_category].visible:
		_select_category(0)


# What each control holds, and the preset-set values that are not on screen.
func _snapshot() -> Dictionary:
	var snap := {"controls": {}, "vars": {}}
	for key in _controls:
		var c = _controls[key]
		if c is SpinBox:
			snap.controls[key] = c.value
		elif c is OptionButton:
			snap.controls[key] = c.selected
	for name in PLAIN_VARS:
		var v = get(name)
		snap.vars[name] = v.duplicate() if v is Array else v
	return snap


# Puts back everything in the snapshot except the skipped controls, without firing their change signals.
func _restore(snap: Dictionary, skip: Array, restore_vars: bool) -> void:
	for key in snap.controls:
		if key in skip:
			continue
		var c = _controls[key]
		if c is SpinBox:
			c.set_block_signals(true)
			c.value = snap.controls[key]
			c.set_block_signals(false)
		elif c is OptionButton:
			c.select(snap.controls[key])
	if restore_vars:
		for name in snap.vars:
			var v = snap.vars[name]
			set(name, v.duplicate() if v is Array else v)


# Resets one category to the preset: the whole preset is applied, then every other category is put back as it was.
func _reset_category(index: int) -> void:
	var keys: Array = CATEGORY_KEYS[CATEGORIES[index]]
	var snap := _snapshot()
	_on_preset_selected(_preset_button.selected)
	_restore(snap, keys, index != 0) # the Engine page owns the preset's firing and bank values; the others keep theirs
	_refresh_feature_switches()
	changed.emit()


# One section: a column that holds its own grid. The first one is shown; the dropdown switches the others in.
func _page(host: Control, title: String) -> GridContainer:
	var page := VBoxContainer.new()
	page.name = title
	page.visible = host.get_child_count() == 0
	page.add_theme_constant_override("separation", 8)
	host.add_child(page)
	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_color_override("font_color", HEADING)
	page.add_child(title_label)
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


# The label _spin/_option already added in front of a control (they add it through _row).
func _label_of(control: Control) -> Label:
	return control.get_parent().get_child(control.get_index() - 1) as Label


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


func _refresh_builds(selected := "") -> void:
	PanelBuilds.refresh(self, selected)


func _save_build() -> void:
	PanelBuilds.save_build(self)


func _load_build() -> void:
	PanelBuilds.load_build(self)


func apply_to(spec: EngineSpec) -> void:
	PanelSpec.apply(self, spec)


func _on_preset_selected(index: int) -> void:
	PanelPresets.select_preset(self, index)
