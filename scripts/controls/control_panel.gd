class_name ControlPanel
extends CanvasLayer

# Left-hand panel: the engine kill switch, the engine preset, then one section at a time (engine, air and fuel, valves, timing,
# tuning), then the warning and the readouts. Changes are reported through signals; main.gd applies them to the simulation.
# Each section holds one label and one value per row, so the panel does not crowd the screen.

signal changed
signal refuel_pressed
signal kill_switch_changed(killed: bool)

const PANEL_WIDTH := 340.0 # wider and larger text for touch; the bottom-left touch pads sit beside its lower edge
const PANEL_FONT := 18 # text size on the panel, up from the default 16
const CONTROL_HEIGHT := 40.0 # minimum height of a spin box, dropdown or button, so they are easy to hit
const ACCENT := Color(0.25, 0.55, 0.9)
const BUTTON := Color(0.16, 0.17, 0.21)
const HEADING := Color(0.55, 0.75, 1.0)
const LABEL_WIDTH := 132.0

var rod_ratio := 1.6 # not on screen, set by the preset
var compression_ratio := 11.3 # not on screen, set by the preset
var crossplane := false # not on screen, set by the preset
var fire_deg: Array = [] # not on screen, set by the preset: the engine's ignition wiring, so the firing matches it
var bank_angle := 90.0 # not on screen, set by the preset
var vehicle_kg := 215.0 # not on screen, set by the preset
var primary_ratio := 3.26 # gearbox values, set by the preset (defaults: K45R)
var final_drive := 3.0
var gear_ratios: Array = Gearbox.ratios()
var _controls := {}
var _warning: Label
var _throttle_label: Label
var _sensor_label: Label
var _twin_label: Label
var _kill_button: Button


func _ready() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	panel.add_theme_stylebox_override("panel", _box(Color(0.06, 0.06, 0.08, 0.93), 12, 14))
	var theme := Theme.new()
	theme.default_font_size = PANEL_FONT
	panel.theme = theme
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	# the engine kill switch, always in view: RUN lets the engine start and run, KILLED cuts the ignition
	_kill_button = Button.new()
	_kill_button.toggle_mode = true
	_kill_button.focus_mode = Control.FOCUS_NONE
	_kill_button.custom_minimum_size = Vector2(0, 52)
	_kill_button.tooltip_text = "Engine kill switch (K): RUN to start and run, KILLED to cut the ignition"
	_kill_button.toggled.connect(_on_kill_toggled)
	_style_kill(false)
	box.add_child(_kill_button)

	var preset := OptionButton.new()
	for preset_name in Presets.PRESETS.keys():
		preset.add_item(preset_name)
	preset.item_selected.connect(_on_preset_selected)
	box.add_child(preset)

	# one section at a time, picked from this dropdown: the panel stays as tall as the section it shows
	var section := OptionButton.new()
	for title in ["Engine", "Air and fuel", "Valves", "Timing", "Tuning"]:
		section.add_item(title)
	box.add_child(section)
	var pages := VBoxContainer.new()
	box.add_child(pages)
	section.item_selected.connect(func(i: int) -> void: _show_section(pages, i))

	var engine := _page(pages, "Engine")
	_controls["cyl"] = _spin(engine, "Cylinders", 1, 16, 1, 1)
	_controls["bore"] = _spin(engine, "Bore (mm)", 30, 150, 0.1, 57.3)
	_controls["stroke"] = _spin(engine, "Stroke (mm)", 20, 150, 0.1, 57.8)
	_controls["layout"] = _option(engine, "Layout", ["inline", "V"])
	_controls["twin"] = OptionButton.new()
	for item in ["360", "270", "180"]:
		_controls["twin"].add_item(item)
	_controls["twin"].item_selected.connect(func(_i: int) -> void: changed.emit())
	_controls["twin"].tooltip_text = "Crank pin angle, 2-cylinder inline only"
	_twin_label = _row(engine, "Crank pin", _controls["twin"])
	_controls["cyl"].value_changed.connect(func(_v: float) -> void: _refresh_twin())
	_controls["layout"].item_selected.connect(func(_i: int) -> void: _refresh_twin())
	_refresh_twin()

	var air := _page(pages, "Air and fuel")
	_controls["header"] = _option(air, "Header", ["stock", "4-1", "4-2-1"])
	_controls["fuel"] = _option(air, "Fuel", FuelTank.LABELS)
	_controls["fuel"].select(FuelTank.KINDS.find("ron95")) # RON 95 is the default, as before the grades were added
	_controls["fuel"].tooltip_text = "Higher RON resists knock, so the ignition can run more advance. E85 also cools the intake charge"
	_controls["lambda"] = _spin(air, "Mixture λ", 0.6, 1.4, 0.01, 1.0)
	_controls["lambda"].tooltip_text = "1.0 = stoichiometric"
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
	_controls["idle"] = _spin(tuning, "Idle speed (rpm)", 400, 4000, 10, 1200)
	_controls["idle"].tooltip_text = "The rpm the ECU holds at idle with the throttle closed, like the idle screw on a real bike"
	_controls["flywheel"] = _spin(tuning, "Flywheel (kg)", 0.5, 10.0, 0.01, 2.5)
	_controls["flywheel_r"] = _spin(tuning, "Flywheel radius (mm)", 20, 150, 0.1, 75.0)

	_warning = Label.new()
	_warning.modulate = Color(1.0, 0.7, 0.3)
	_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_warning)

	# the readouts sit in their own dark box so they read as a display, not as settings
	var readout := PanelContainer.new()
	readout.add_theme_stylebox_override("panel", _box(Color(0.0, 0.0, 0.0, 0.5), 8, 8))
	box.add_child(readout)
	_throttle_label = Label.new()
	_throttle_label.add_theme_font_size_override("font_size", PANEL_FONT - 1)
	_throttle_label.add_theme_color_override("font_color", Color(0.82, 0.84, 0.9))
	_throttle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	readout.add_child(_throttle_label)
	# the sensors sit in a second box under the engine readout
	var sensors := PanelContainer.new()
	sensors.add_theme_stylebox_override("panel", _box(Color(0.0, 0.0, 0.0, 0.5), 8, 8))
	box.add_child(sensors)
	_sensor_label = Label.new()
	_sensor_label.add_theme_font_size_override("font_size", PANEL_FONT - 2)
	_sensor_label.add_theme_color_override("font_color", Color(0.75, 0.9, 0.8))
	_sensor_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sensors.add_child(_sensor_label)


# Copies the panel's values into the engine spec.
func apply_to(spec: EngineSpec) -> void:
	var layout: OptionButton = _controls["layout"]
	var header: OptionButton = _controls["header"]
	var fuel: OptionButton = _controls["fuel"]
	spec.cylinders = int(_controls["cyl"].value)
	spec.bore_mm = _controls["bore"].value
	spec.stroke_mm = _controls["stroke"].value
	# displacement is not an input: it follows from bore, stroke and cylinder count
	spec.displacement_cc = Units.displacement_cc(spec.bore_mm, spec.stroke_mm, spec.cylinders)
	spec.layout = layout.get_item_text(layout.selected)
	var twin: OptionButton = _controls["twin"]
	spec.twin_pin_deg = float(twin.get_item_text(twin.selected))
	spec.header = header.get_item_text(header.selected)
	spec.fuel = FuelTank.KINDS[fuel.selected]
	spec.rod_ratio = rod_ratio
	spec.compression_ratio = compression_ratio
	spec.crossplane = crossplane
	spec.fire_deg = fire_deg
	spec.bank_angle = bank_angle
	spec.vehicle_kg = vehicle_kg
	spec.primary_ratio = primary_ratio
	spec.final_drive = final_drive
	spec.gear_ratios = gear_ratios
	spec.redline_rpm = _controls["redline"].value
	spec.flywheel_kg = _controls["flywheel"].value
	spec.flywheel_radius_mm = _controls["flywheel_r"].value
	spec.intake_duration_deg = _controls["in_dur"].value
	spec.intake_lift_mm = _controls["in_lift"].value
	spec.intake_centre_deg = _controls["in_centre"].value
	spec.exhaust_duration_deg = _controls["ex_dur"].value
	spec.exhaust_lift_mm = _controls["ex_lift"].value
	spec.exhaust_centre_deg = _controls["ex_centre"].value
	spec.ignition_offset_deg = _controls["timing"].value
	spec.idle_target_rpm = _controls["idle"].value


func lambda() -> float:
	return _controls["lambda"].value


func set_warning(text: String) -> void:
	_warning.text = text


func set_sensor_text(text: String) -> void:
	_sensor_label.text = text


func set_throttle_text(text: String) -> void:
	_throttle_label.text = text


# The crank-pin angle only matters for a 2-cylinder inline engine, so only then is it shown.
func _refresh_twin() -> void:
	var layout: OptionButton = _controls["layout"]
	var twin_applies: bool = int(_controls["cyl"].value) == 2 and layout.get_item_text(layout.selected) == "inline"
	_twin_label.visible = twin_applies
	_controls["twin"].visible = twin_applies


# Flips the kill switch, as the K key does.
func toggle_kill() -> void:
	_kill_button.button_pressed = not _kill_button.button_pressed


func _on_kill_toggled(killed: bool) -> void:
	_style_kill(killed)
	kill_switch_changed.emit(killed)


# Green RUN when the engine may run, red KILLED when the ignition is cut.
func _style_kill(killed: bool) -> void:
	_kill_button.text = "ENGINE KILLED  (K)" if killed else "ENGINE RUN  (K)"
	var fill := Color(0.72, 0.13, 0.13) if killed else Color(0.13, 0.46, 0.22)
	for state in ["normal", "pressed", "hover", "focus"]:
		_kill_button.add_theme_stylebox_override(state, _box(fill.lightened(0.1) if state == "hover" else fill, 8, 8))


func _on_preset_selected(index: int) -> void:
	var p: Dictionary = Presets.PRESETS.values()[index]
	_set_quiet(_controls["cyl"], p.cylinders)
	_set_quiet(_controls["bore"], p.bore_mm)
	_set_quiet(_controls["stroke"], p.stroke_mm)
	_select_text(_controls["layout"], p.layout)
	_select_text(_controls["header"], p.header)
	_controls["fuel"].select(FuelTank.KINDS.find(p.fuel))
	_select_text(_controls["twin"], str(int(p.get("twin_pin_deg", 360.0))))
	_set_quiet(_controls["redline"], p.redline_rpm)
	_set_quiet(_controls["flywheel"], p.flywheel_kg)
	_set_quiet(_controls["flywheel_r"], p.flywheel_radius_mm)
	# the cams and timing go back to the stock values (or the preset's own) when a preset is picked
	_set_quiet(_controls["in_dur"], 240.0)
	_set_quiet(_controls["in_lift"], 6.0)
	_set_quiet(_controls["in_centre"], 470.0)
	_set_quiet(_controls["ex_dur"], 230.0)
	_set_quiet(_controls["ex_lift"], 5.0)
	_set_quiet(_controls["ex_centre"], 255.0)
	_set_quiet(_controls["timing"], 0.0)
	_set_quiet(_controls["idle"], 1200.0)
	rod_ratio = p.rod_ratio
	compression_ratio = p.get("compression_ratio", 11.3)
	crossplane = p.get("crossplane", false)
	fire_deg = p.get("fire_deg", [])
	bank_angle = p.get("bank_angle", 90.0)
	vehicle_kg = p.get("vehicle_kg", 215.0)
	# gearbox: K45R values unless the preset gives its own
	primary_ratio = p.get("primary_ratio", 3.26)
	final_drive = p.get("final_drive", 3.0)
	gear_ratios = p.get("gear_ratios", Gearbox.ratios())
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
