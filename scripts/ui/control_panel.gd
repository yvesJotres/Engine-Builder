class_name ControlPanel
extends CanvasLayer

# Left-hand panel: engine preset and settings, ignition, starter, refuel, sound, readouts.
# Changes are reported through signals; main.gd applies them to the simulation.
# Settings sit under short headings, one label and one value per row, so they scan quickly.

signal changed
signal refuel_pressed
signal ignition_changed(on: bool)
signal starter_changed(held: bool)

const PANEL_WIDTH := 300.0 # the touch pads start at x = 340 on the 1920x1080 layout, so this keeps clear of them
const ACCENT := Color(0.25, 0.55, 0.9)
const BUTTON := Color(0.16, 0.17, 0.21)
const HEADING := Color(0.55, 0.75, 1.0)
const LABEL_WIDTH := 132.0

var rod_ratio := 1.6 # not on screen, set by the preset
var compression_ratio := 11.3 # not on screen, set by the preset
var crossplane := false # not on screen, set by the preset
var vehicle_kg := 215.0 # not on screen, set by the preset
var primary_ratio := 3.26 # gearbox values, set by the preset (defaults: K45R)
var final_drive := 3.0
var gear_ratios: Array = Gearbox.ratios()
var _controls := {}
var _warning: Label
var _throttle_label: Label
var _twin_label: Label
var _ignition_label: Label


func _ready() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	panel.add_theme_stylebox_override("panel", _box(Color(0.06, 0.06, 0.08, 0.93), 12, 14))
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	box.add_child(_heading("Engine"))
	var preset := OptionButton.new()
	for preset_name in Presets.PRESETS.keys():
		preset.add_item(preset_name)
	preset.item_selected.connect(_on_preset_selected)
	box.add_child(preset)
	var engine := _grid(box)
	# defaults: Honda CBR150R (K45N) reference for measurement study
	_controls["cyl"] = _spin(engine, "Cylinders", 1, 16, 1, 1)
	_controls["bore"] = _spin(engine, "Bore (mm)", 40, 150, 0.1, 57.3)
	_controls["stroke"] = _spin(engine, "Stroke (mm)", 40, 150, 0.1, 57.8)
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

	box.add_child(_heading("Intake and exhaust"))
	var intake := _grid(box)
	_controls["header"] = _option(intake, "Header", ["stock", "4-1", "4-2-1"])
	_controls["fuel"] = _option(intake, "Fuel", ["petrol", "e85"])
	_controls["lambda"] = _spin(intake, "Mixture λ", 0.6, 1.4, 0.01, 1.0)
	_controls["lambda"].tooltip_text = "1.0 = stoichiometric"

	box.add_child(_heading("Tuning"))
	var tuning := _grid(box)
	_controls["redline"] = _spin(tuning, "Redline (rpm)", 2000, 20000, 100, 10600)
	_controls["redline"].tooltip_text = "Fuel is cut at this speed"
	_controls["flywheel"] = _spin(tuning, "Flywheel (kg)", 0.5, 10.0, 0.01, 2.5)
	_controls["flywheel_r"] = _spin(tuning, "Flywheel radius (mm)", 20, 150, 0.5, 75.0)

	box.add_child(_heading("Controls"))
	var ignition := HBoxContainer.new()
	ignition.add_theme_constant_override("separation", 12)
	box.add_child(ignition)
	var knob := IgnitionKnob.new()
	knob.toggled.connect(_on_ignition_toggled)
	ignition.add_child(knob)
	var knob_text := VBoxContainer.new()
	knob_text.alignment = BoxContainer.ALIGNMENT_CENTER
	knob_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ignition.add_child(knob_text)
	_ignition_label = Label.new()
	_ignition_label.text = "Ignition OFF"
	knob_text.add_child(_ignition_label)
	var knob_hint := Label.new()
	knob_hint.text = "Click the knob"
	knob_hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.66))
	knob_text.add_child(knob_hint)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)
	var refuel := _button("Refuel", buttons)
	refuel.pressed.connect(func() -> void: refuel_pressed.emit())
	var starter := _button("Starter (hold)", buttons)
	starter.button_down.connect(func() -> void: starter_changed.emit(true))
	starter.button_up.connect(func() -> void: starter_changed.emit(false))


	_warning = Label.new()
	_warning.modulate = Color(1.0, 0.7, 0.3)
	_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_warning)

	# the readouts sit in their own dark box so they read as a display, not as settings
	var readout := PanelContainer.new()
	readout.add_theme_stylebox_override("panel", _box(Color(0.0, 0.0, 0.0, 0.5), 8, 8))
	box.add_child(readout)
	_throttle_label = Label.new()
	_throttle_label.add_theme_font_size_override("font_size", 15)
	_throttle_label.add_theme_color_override("font_color", Color(0.82, 0.84, 0.9))
	_throttle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	readout.add_child(_throttle_label)


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
	spec.fuel = fuel.get_item_text(fuel.selected)
	spec.rod_ratio = rod_ratio
	spec.compression_ratio = compression_ratio
	spec.crossplane = crossplane
	spec.vehicle_kg = vehicle_kg
	spec.primary_ratio = primary_ratio
	spec.final_drive = final_drive
	spec.gear_ratios = gear_ratios
	spec.redline_rpm = _controls["redline"].value
	spec.flywheel_kg = _controls["flywheel"].value
	spec.flywheel_radius_mm = _controls["flywheel_r"].value


func lambda() -> float:
	return _controls["lambda"].value


func set_warning(text: String) -> void:
	_warning.text = text


func set_throttle_text(text: String) -> void:
	_throttle_label.text = text


# The crank-pin angle only matters for a 2-cylinder inline engine, so only then is it shown.
func _refresh_twin() -> void:
	var layout: OptionButton = _controls["layout"]
	var twin_applies: bool = int(_controls["cyl"].value) == 2 and layout.get_item_text(layout.selected) == "inline"
	_twin_label.visible = twin_applies
	_controls["twin"].visible = twin_applies




func _on_ignition_toggled(on: bool) -> void:
	_ignition_label.text = "Ignition ON" if on else "Ignition OFF"
	ignition_changed.emit(on)


func _on_preset_selected(index: int) -> void:
	var p: Dictionary = Presets.PRESETS.values()[index]
	_set_quiet(_controls["cyl"], p.cylinders)
	_set_quiet(_controls["bore"], p.bore_mm)
	_set_quiet(_controls["stroke"], p.stroke_mm)
	_select_text(_controls["layout"], p.layout)
	_select_text(_controls["header"], p.header)
	_select_text(_controls["fuel"], p.fuel)
	_select_text(_controls["twin"], str(int(p.get("twin_pin_deg", 360.0))))
	_set_quiet(_controls["redline"], p.redline_rpm)
	_set_quiet(_controls["flywheel"], p.flywheel_kg)
	_set_quiet(_controls["flywheel_r"], p.flywheel_radius_mm)
	rod_ratio = p.rod_ratio
	compression_ratio = p.get("compression_ratio", 11.3)
	crossplane = p.get("crossplane", false)
	vehicle_kg = p.get("vehicle_kg", 215.0)
	# gearbox: K45R values unless the preset gives its own
	primary_ratio = p.get("primary_ratio", 3.26)
	final_drive = p.get("final_drive", 3.0)
	gear_ratios = p.get("gear_ratios", Gearbox.ratios())
	_refresh_twin() # set_quiet does not signal, so update the crank-pin row here
	changed.emit()


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
	s.value_changed.connect(func(_v: float) -> void: changed.emit())
	_row(grid, label, s)
	return s


func _option(grid: GridContainer, label: String, items: Array) -> OptionButton:
	var o := OptionButton.new()
	for item in items:
		o.add_item(item)
	o.item_selected.connect(func(_i: int) -> void: changed.emit())
	_row(grid, label, o)
	return o


# Buttons are tall and wide enough to hit with a thumb on a phone.
func _button(text: String, parent: Control) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 52)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(b)
	parent.add_child(b)
	return b


func _style_button(b: Button) -> void:
	b.add_theme_stylebox_override("normal", _box(BUTTON, 8, 8))
	b.add_theme_stylebox_override("hover", _box(BUTTON.lightened(0.12), 8, 8))
	b.add_theme_stylebox_override("pressed", _box(ACCENT, 8, 8)) # lit while held, or while Sound is on


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", HEADING)
	return l


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
