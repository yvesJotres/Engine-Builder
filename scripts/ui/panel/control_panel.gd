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
const PANEL_MARGIN := 16.0 # gap between the panel and the screen edge
const GAP := 8 # space between sections and rows
const GAP_TIGHT := 6 # space between the fixed-top rows
const TAB_COLUMNS := 4
const TAB_HEIGHT := 36.0
const TAB_FONT := 14
const BOX_RADIUS := 8
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
var exhaust_valve_mm := 17.0
var wall_heat_scale := 1.0
var valve_cd := 0.7
var final_drive := 3.0
var gear_ratios: Array = Gearbox.ratios()
var _vehicle_settings := {}
var _controls := {}
var _feature_labels := {}
var _visibility_conditions := {} # key -> condition name, for schema-driven visibility
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
var _four_stroke_rows: Array[Control] = [] # the valve and runner rows: a two-stroke has no valves
var _firing_rows: Array[Control] = [] # the firing-order rows: only a multi-cylinder engine has a firing order
var _warning: Label
var builds_path := "user://engine_builds.cfg"
var _build_name: LineEdit
var _builds: OptionButton
var _build_status: Label
var _overwrite_dialog: ConfirmationDialog
var _pending_build := ""
var _delete_dialog: ConfirmationDialog
var _pending_delete := ""

# Categories, tabs, category keys, and plain vars are defined in PanelSchema.
# ControlPanel re-exports them for convenience and backward compatibility with tests.
const CATEGORIES := PanelSchema.CATEGORIES
const CATEGORY_TABS := PanelSchema.CATEGORY_TABS
const CATEGORY_KEYS := PanelSchema.CATEGORY_KEYS
const PLAIN_VARS := PanelSchema.PLAIN_VARS
var _tabs: Array[Button] = []
var _pages_root: VBoxContainer
var _category := 0
var _changed_pending := false

func _ready() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	panel.offset_left = PANEL_MARGIN
	panel.offset_top = PANEL_MARGIN
	panel.offset_right = PANEL_WIDTH + PANEL_MARGIN
	panel.offset_bottom = -PANEL_MARGIN
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
	render_btn.tooltip_text = "Renders the exhaust sound offline and asks where to save the WAV file."
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
	var rename_build := Button.new()
	rename_build.text = "Rename"
	rename_build.tooltip_text = "Renames the selected build to the name typed above"
	rename_build.pressed.connect(_rename_build)
	load_row.add_child(rename_build)
	var delete_build := Button.new()
	delete_build.text = "Delete"
	delete_build.tooltip_text = "Deletes the selected build"
	delete_build.pressed.connect(_delete_build)
	load_row.add_child(delete_build)
	_build_status = Label.new()
	_build_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	builds_box.add_child(_build_status)
	_refresh_builds()

	# load the engine library from the server
	ENGINE_LIBRARY.get_instance().library_ready.connect(_on_library_ready)
	ENGINE_LIBRARY.get_instance().fetch()

	# the category tabs: one page at a time, so the panel is as tall as the page it shows
	var tab_grid := GridContainer.new()
	tab_grid.columns = TAB_COLUMNS
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
		tab.custom_minimum_size.y = TAB_HEIGHT
		tab.add_theme_font_size_override("font_size", TAB_FONT)
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
	pages_box.add_theme_constant_override("separation", GAP)
	pages_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pages_box)
	var pages := VBoxContainer.new()
	pages_box.add_child(pages)
	_pages_root = pages
	# the nine pages, in the order of the tabs
	var engine := _page(pages, "Engine")
	var air := _page(pages, "Intake and fuel")
	var exhaust := _page(pages, "Exhaust")
	var valves := _page(pages, "Valvetrain")
	var timing_page := _page(pages, "Ignition")
	var boost := _page(pages, "Forced induction")
	var aids := _page(pages, "Rider aids")
	var vehicle := _page(pages, "Vehicle")
	var sound := _page(pages, "Sound")
	# Build all schema-driven controls (spin, option, toggle) across every page.
	# Special controls (bank_angle, shared_pins, twin, custom_pin, crank,
	# firing_order, compressor_map_view) are created below this block.
	PanelSchema.set_fuel_items(FuelTank.LABELS)
	var page_by_category := {
		"Engine": engine,
		"Intake and fuel": air,
		"Exhaust": exhaust,
		"Valvetrain": valves,
		"Ignition": timing_page,
		"Forced induction": boost,
		"Rider aids": aids,
		"Vehicle": vehicle,
		"Sound": sound,
	}
	for key in PanelSchema.all_keys():
		var def: Dictionary = PanelSchema.get_def(key)
		if (def.type == "special"):
			continue
		var grid: GridContainer = page_by_category[def.category]
		var control: Control
		if (def.type == "spin"):
			control = _spin(grid, def.label, def.min, def.max, def.step, def.default)
		elif (def.type == "option"):
			var items: Array = def.items
			if key == "fuel":
				items = PanelSchema.get_fuel_items()
			control = _option(grid, def.label, items)
		elif (def.type == "toggle"):
			control = ToggleSwitch.new()
			control.add_item("Off")
			control.add_item("On")
			control.custom_minimum_size.y = CONTROL_HEIGHT
			control.item_selected.connect(func(_i: int) -> void: _emit_changed())
			_row(grid, def.label, control)
		if def.has("tooltip"):
			control.tooltip_text = def.tooltip
		_controls[key] = control
		if PanelSchema.is_visible_conditional(key):
			_visibility_conditions[key] = PanelSchema.visible_condition(key)

	# ---- Engine special controls ----
	var bank := SpinBox.new()
	bank.min_value = 1.0
	bank.max_value = 180.0
	bank.step = 1.0
	bank.value = bank_angle
	bank.custom_minimum_size.y = CONTROL_HEIGHT
	bank.tooltip_text = PanelSchema.get_def("bank_angle").tooltip
	_controls["bank_angle"] = bank
	_bank_label = _row(engine, PanelSchema.get_def("bank_angle").label, bank)
	bank.value_changed.connect(func(value: float) -> void:
		bank_angle = value
		_refresh_firing_order()
		_emit_changed())

	_controls["shared_pins"] = OptionButton.new()
	_controls["shared_pins"].add_item("Preset / automatic")
	_controls["shared_pins"].add_item("Shared opposite-bank pairs")
	_controls["shared_pins"].tooltip_text = PanelSchema.get_def("shared_pins").tooltip
	_shared_pins_label = _row(engine, PanelSchema.get_def("shared_pins").label, _controls["shared_pins"])
	_controls["shared_pins"].item_selected.connect(func(_index: int) -> void:
		_refresh_firing_order()
		_emit_changed())

	_controls["twin"] = OptionButton.new()
	for item in PanelSchema.get_def("twin").items:
		_controls["twin"].add_item(item)
	_controls["twin"].item_selected.connect(_on_twin_selected)
	_controls["twin"].tooltip_text = PanelSchema.get_def("twin").tooltip
	_twin_label = _row(engine, PanelSchema.get_def("twin").label, _controls["twin"])

	_controls["custom_pin"] = SpinBox.new()
	_controls["custom_pin"].min_value = 1.0
	_controls["custom_pin"].max_value = 359.0
	_controls["custom_pin"].step = 1.0
	_controls["custom_pin"].value = 270.0
	_custom_pin_label = _row(engine, PanelSchema.get_def("custom_pin").label, _controls["custom_pin"])
	_controls["custom_pin"].value_changed.connect(func(_v: float) -> void:
		if _controls["twin"].get_item_text(_controls["twin"].selected) == "Custom":
			_on_twin_selected(_controls["twin"].selected))

	_controls["crank"] = OptionButton.new()
	_crank_label = _row(engine, PanelSchema.get_def("crank").label, _controls["crank"])
	_controls["crank"].item_selected.connect(_on_crank_selected)

	_firing_order = LineEdit.new()
	_firing_order.placeholder_text = "e.g. 1-3-4-2"
	_firing_order.tooltip_text = PanelSchema.get_def("firing_order").tooltip
	_firing_rows.append(_row(engine, PanelSchema.get_def("firing_order").label, _firing_order))
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
		_emit_changed())
	_controls["layout"].item_selected.connect(func(_i: int) -> void: _refresh_twin())
	_refresh_twin()

	# Schema-created controls exist; apply remaining special-case setup.
	# Exhaust: extra header_primary_mm control not in schema.
	var header_primary_mm := _spin(exhaust, "Primary pipe (mm)", 20.0, 60.0, 0.5, 32.0)
	header_primary_mm.tooltip_text = "Header primary pipe diameter. Per-bike values are seller or similar-bike estimates, not OEM measurements."
	_controls["header_primary_mm"] = header_primary_mm

	_controls["live_exhaust_physics"].tooltip_text = PanelSchema.get_def("live_exhaust_physics").tooltip
	var exhaust_note := Label.new()
	exhaust_note.text = "Experimental: affects torque; uses more CPU"
	exhaust_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_row(exhaust, "", exhaust_note)
	# Four-stroke rows: track valve and runner controls for visibility toggling.
	for key in ["intake_valve_mm", "runner_length_m"]:
		var spin: SpinBox = _controls[key]
		_four_stroke_rows.append(air.get_child(spin.get_index() - 1)) # the label beside the control
		_four_stroke_rows.append(spin)

	var intake_note := Label.new()
	intake_note.text = "Visual only · four-stroke fuel injection"
	intake_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_row(air, "", intake_note)

	_controls["fuel"].select(FuelTank.KINDS.find("ron95")) # RON 95 is the default, as before the grades were added
	_controls["lambda"].tooltip_text = PanelSchema.get_def("lambda").tooltip
	var refuel := Button.new()
	refuel.text = "Refuel"
	refuel.focus_mode = Control.FOCUS_NONE
	refuel.custom_minimum_size = Vector2(0, 40)
	_style_button(refuel)
	refuel.pressed.connect(func() -> void: refuel_pressed.emit())
	_row(air, "Tank", refuel)



	var timing_hint := Label.new()
	timing_hint.text = "+ advances, - retards. Past the knock limit the engine knocks."
	timing_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	timing_hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.66))
	timing_page.add_child(timing_hint)

	_controls["idle"].tooltip_text = PanelSchema.get_def("idle").tooltip
	_controls["power_mode"].tooltip_text = PanelSchema.get_def("power_mode").tooltip

	# Rider aids: feature label mappings.
	_feature_labels["qs_enabled"] = _label_of(_controls["qs_enabled"])
	_feature_labels["qs_sensitivity"] = _label_of(_controls["qs_sensitivity"])
	_feature_labels["qs_cut_base"] = _label_of(_controls["qs_cut_base"])
	_feature_labels["qs_blip_time"] = _label_of(_controls["qs_blip_time"])
	_feature_labels["qs_blip_throttle"] = _label_of(_controls["qs_blip_throttle"])
	_feature_labels["qs_flat_shift"] = _label_of(_controls["qs_flat_shift"])

	_controls["launch_control"].tooltip_text = PanelSchema.get_def("launch_control").tooltip
	_feature_labels["launch_control"] = _label_of(_controls["launch_control"])
	_controls["abs_enabled"].tooltip_text = PanelSchema.get_def("abs_enabled").tooltip
	_feature_labels["abs_enabled"] = _label_of(_controls["abs_enabled"])
	_controls["traction_control_enabled"].tooltip_text = PanelSchema.get_def("traction_control_enabled").tooltip
	_feature_labels["traction_control_enabled"] = _label_of(_controls["traction_control_enabled"])
	_controls["slipper_clutch"].tooltip_text = PanelSchema.get_def("slipper_clutch").tooltip

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

	_refresh_feature_switches()



func lambda() -> float:
	return _controls["lambda"].value


func set_warning(text: String) -> void:
	_warning.text = text


func _refresh_twin() -> void:
	var layout: OptionButton = _controls["layout"]
	var count := int(_controls["cyl"].value)
	for node in _firing_rows:
		node.visible = count > 1
	var four_stroke: bool = _controls["stroke_type"].selected == 0
	for node in _four_stroke_rows:
		node.visible = four_stroke
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
	_emit_changed()


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
	_emit_changed()


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
	_emit_changed()


# Flips the kill switch, as the K key does.
func toggle_kill() -> void:
	_kill_button.button_pressed = not _kill_button.button_pressed


func _populate_preset_dropdown(library: Dictionary) -> void:
	# The dropdown order matches Presets.names() (filename order): tests and _on_preset_selected address presets by that index.
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
	# Select CBR150R as the visible default; the controls stay at the spec defaults until a preset is chosen.
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
	var option := ToggleSwitch.new()
	option.add_item("Off")
	option.add_item("On")
	option.custom_minimum_size.y = CONTROL_HEIGHT
	option.tooltip_text = tooltip
	option.item_selected.connect(func(_index: int) -> void: _emit_changed())
	_controls[key] = option
	_feature_labels[key] = _row(grid, label_text, option)


func _refresh_feature_switches() -> void:
	# every aid is on every bike: the factory fit only sets its default, which the preset applies.
	# ABS and traction control stay locked until their wheel-slip physics is built.
	for key in ["abs_enabled", "traction_control_enabled"]:
		_controls[key].visible = WHEEL_AIDS_AVAILABLE # hidden, not greyed out, until the physics exists
		_feature_labels[key].visible = WHEEL_AIDS_AVAILABLE
		_controls[key].disabled = not WHEEL_AIDS_AVAILABLE
		if not WHEEL_AIDS_AVAILABLE:
			_controls[key].select(0)

	# Quickshifter detailed controls visibility
	var qs_visible := true
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


# Many controls change at once on a preset or a drag. Listeners get one changed per frame, not one per control.
func _emit_changed() -> void:
	if _changed_pending:
		return
	_changed_pending = true
	_flush_changed.call_deferred()


func _flush_changed() -> void:
	_changed_pending = false
	changed.emit()


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
	_tabs[5].visible = boosted
	_tabs[6].visible = true # every bike can use the aids; the factory fit only sets the default
	if not _tabs[_category].visible:
		_select_category(0)


# What each control holds, and the preset-set values that are not on screen.
func _snapshot() -> Dictionary:
	var snap := {"controls": {}, "vars": {}}
	for key in _controls:
		var c = _controls[key]
		if c is SpinBox:
			snap.controls[key] = c.value
		elif c is OptionButton or c is ToggleSwitch:
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
		elif c is OptionButton or c is ToggleSwitch:
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
	_emit_changed()


# One section: a column that holds its own grid. The first one is shown; the dropdown switches the others in.
func _page(host: Control, title: String) -> GridContainer:
	var page := VBoxContainer.new()
	page.name = title
	page.visible = host.get_child_count() == 0
	page.add_theme_constant_override("separation", GAP)
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
	s.value_changed.connect(func(_v: float) -> void: _emit_changed())
	_row(grid, label, s)
	return s


# An on/off switch in a row, for the Off/On settings. A tap emits changed, like the other controls.
func _toggle(grid: GridContainer, label: String) -> ToggleSwitch:
	var toggle := ToggleSwitch.new()
	toggle.add_item("Off")
	toggle.add_item("On")
	toggle.custom_minimum_size.y = CONTROL_HEIGHT
	toggle.item_selected.connect(func(_i: int) -> void: _emit_changed())
	_row(grid, label, toggle)
	return toggle


func _option(grid: GridContainer, label: String, items: Array) -> OptionButton:
	var o := OptionButton.new()
	for item in items:
		o.add_item(item)
	o.custom_minimum_size.y = CONTROL_HEIGHT
	o.item_selected.connect(func(_i: int) -> void: _emit_changed())
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
	b.add_theme_stylebox_override("normal", _box(BUTTON, BOX_RADIUS, BOX_RADIUS))
	b.add_theme_stylebox_override("hover", _box(BUTTON.lightened(0.12), BOX_RADIUS, BOX_RADIUS))
	b.add_theme_stylebox_override("pressed", _box(ACCENT, BOX_RADIUS, BOX_RADIUS)) # lit while held, or while Sound is on



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


func _select_text(option, text: String) -> void:
	for i in option.item_count:
		if option.get_item_text(i) == text:
			option.select(i)


func _refresh_builds(selected := "") -> void:
	PanelBuilds.refresh(self, selected)


func _save_build() -> void:
	PanelBuilds.save_build(self)


# Asks before a saved build is replaced; the replace happens only on confirm.
func _confirm_overwrite(build_name: String) -> void:
	if _overwrite_dialog == null:
		_overwrite_dialog = ConfirmationDialog.new()
		_overwrite_dialog.ok_button_text = "Replace"
		_overwrite_dialog.confirmed.connect(func() -> void: PanelBuilds.write_build(self, _pending_build))
		add_child(_overwrite_dialog)
	_pending_build = build_name
	_overwrite_dialog.dialog_text = "Replace the saved build \"%s\"?" % build_name
	_overwrite_dialog.popup_centered()


func _rename_build() -> void:
	PanelBuilds.rename_build(self)


func _delete_build() -> void:
	PanelBuilds.confirm_delete(self)


# Asks before a saved build is deleted; it goes only on confirm.
func _confirm_delete(build_name: String) -> void:
	if _delete_dialog == null:
		_delete_dialog = ConfirmationDialog.new()
		_delete_dialog.ok_button_text = "Delete"
		_delete_dialog.confirmed.connect(func() -> void: PanelBuilds.delete_build(self, _pending_delete))
		add_child(_delete_dialog)
	_pending_delete = build_name
	_delete_dialog.dialog_text = "Delete the saved build \"%s\"? This cannot be undone." % build_name
	_delete_dialog.popup_centered()


func _load_build() -> void:
	PanelBuilds.load_build(self)


func apply_to(spec: EngineSpec) -> void:
	PanelSpec.apply(self, spec)


func _on_preset_selected(index: int) -> void:
	PanelPresets.select_preset(self, index)
