class_name DynoView
extends CanvasLayer

# The dyno test's screen. It sits in the top right and stops above the dashboard, so the engine and the speed cluster stay visible.
# Stop ends a running test; Close hides the screen once the test is over.

signal stop_requested

const BUTTON := Color(0.16, 0.17, 0.21)
const ACCENT := Color(0.25, 0.55, 0.9)
const DIM := Color(0.62, 0.66, 0.74)
const TORQUE_COLOUR := Color(1.0, 0.62, 0.2)
const POWER_COLOUR := Color(0.35, 0.8, 1.0)
const HP_PER_KW := 1.341 # hp per kW: power in hp and kW from the same number
const PANEL_WIDTH := 760.0
const ABOVE_DASH := 266.0 # the dashboard occupies the bottom 250px plus a gap
const GEAR_ROWS := 10
const DYNO_GRAPH_SCRIPT := preload("res://scripts/dyno/dyno_graph.gd")
const ONLINE_DYNO := preload("res://scripts/dyno/online_dyno.gd")

var _root: Control
var _panel: PanelContainer
var _status: Label
var _peaks: Label
var _empty: Label
var _grid: GridContainer
var _rows: Array = []
var _graph
var _button: Button
var _running := false
var _wrote := false
var _reference: Array = []
var _latest_curve: Array = []
var _reference_button: Button
var _comparison: Label
var reference_path := "user://dyno_reference.json"
var _reference_id := ""
var _online: Dictionary = {}
var _basis: OptionButton
var _online_status: Label
var _last_result: Dictionary = {}
var _display_redline := 10000.0


func _ready() -> void:
	layer = 20
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE # clicks outside the panel reach the engine
	_root.visible = false
	add_child(_root)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", _box(Color(0.06, 0.06, 0.08, 0.95), 12, 14))
	_panel.anchor_left = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -PANEL_WIDTH
	_panel.offset_top = 16.0
	_panel.offset_right = -16.0
	_panel.offset_bottom = -ABOVE_DASH
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_root.add_child(_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel.add_child(scroll)
	scroll.add_child(col)
	var title := Label.new()
	title.text = "Dyno test"
	title.add_theme_font_size_override("font_size", 22)
	col.add_child(title)
	_status = Label.new()
	col.add_child(_status)
	_comparison = Label.new()
	_comparison.text = "Torque: orange · Power: blue · Reference torque: grey"
	_basis = OptionButton.new()
	_basis.add_item("Crankshaft")
	_basis.add_item("Estimated rear wheel · Online dyno comparison")
	_basis.custom_minimum_size.y = 36.0
	_basis.visible = false
	_basis.item_selected.connect(func(_index: int) -> void: _display(_last_result))
	col.add_child(_basis)
	_online_status = Label.new()
	_online_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_online_status.add_theme_font_size_override("font_size", 13)
	_online_status.visible = false
	col.add_child(_online_status)
	_comparison.add_theme_color_override("font_color", DIM)
	col.add_child(_comparison)
	_graph = DYNO_GRAPH_SCRIPT.new()
	col.add_child(_graph)
	_peaks = Label.new()
	_peaks.add_theme_font_size_override("font_size", 15)
	col.add_child(_peaks)
	_grid = GridContainer.new()
	_grid.columns = 6
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 2)
	col.add_child(_grid)
	for heading in ["Gear", "N·m", "rpm", "hp", "rpm", "km/h"]:
		var cell := _cell(heading, DIM)
		_grid.add_child(cell)
	for _i in GEAR_ROWS:
		var row: Array = []
		for _c in 6:
			var cell := _cell("", Color(0.9, 0.9, 0.95))
			cell.visible = false
			_grid.add_child(cell)
			row.append(cell)
		_rows.append(row)
	_empty = Label.new()
	_empty.text = "No readings yet."
	_empty.add_theme_color_override("font_color", DIM)
	col.add_child(_empty)
	_reference_button = Button.new()
	_reference_button.text = "Set this run as reference (replaces previous)"
	_reference_button.pressed.connect(_save_reference)
	_style_button(_reference_button)
	col.add_child(_reference_button)
	_reference = _load_reference()
	_button = Button.new()
	_button.custom_minimum_size = Vector2(0, 44)
	_button.focus_mode = Control.FOCUS_NONE
	_style_button(_button)
	_button.pressed.connect(_on_button)
	col.add_child(_button)


func open() -> void:
	_root.visible = true


func is_open() -> bool:
	return _root.visible


# Shows the test as it stands: its status, the curve and the peaks so far.
func refresh(dyno) -> void:
	if _reference_id != dyno.reference_id:
		_reference_id = dyno.reference_id
		_reference = _load_reference()
		_online = ONLINE_DYNO.for_preset(_reference_id)
		_basis.visible = not _online.is_empty()
		_basis.select(1 if not _online.is_empty() else 0)
		_basis.tooltip_text = str(_online.get("source_url", ""))
	_running = dyno.active()
	_button.text = "Stop test" if _running else "Close"
	var r: Dictionary = dyno.result()
	_latest_curve = r.curve
	_last_result = r
	_status.text = ("IN PROGRESS · " if _running else ("COMPLETE · " if r.ok else "INCOMPLETE · ")) + dyno.status_text()
	_status.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95) if r.ok else Color(1.0, 0.55, 0.45))
	_display_redline = dyno.redline()
	if _running:
		_wrote = false
	elif not _wrote and not r.curve.is_empty():
		_wrote = true
		DynoTest.write_result(r, "user://dyno_last")
	_display(r)


func _display(r: Dictionary) -> void:
	if r.is_empty():
		return
	var wheel := _basis.selected == 1 and not _online.is_empty()
	_reference_button.disabled = wheel or _running or not r.ok or r.curve.is_empty()
	var normalization := ONLINE_DYNO.comparison_factor(_online)
	var shown: Dictionary = ONLINE_DYNO.wheel_result(r, normalization) if wheel else r
	_graph.set_curve(shown.curve, _display_redline)
	_graph.set_reference(ONLINE_DYNO.reference_curve(_online) if wheel else _reference, wheel)
	_comparison.text = "Torque: orange · Power: blue · Online: grey torque / dashed power" if wheel else "Torque: orange · Power: blue · Saved reference torque: grey"
	_online_status.visible = not _online.is_empty()
	if not _online.is_empty():
		_online_status.text = "%s · %.2f wheel hp / %.2f N·m · DIN\nWheel estimate: %.0f%% efficiency × %.4f DIN normalization (model air: 300 K, 101325 Pa). Approximate online curve; fourth-gear roller protocol not reproduced." % [
			_online.title, _online.peak_power_hp, _online.peak_torque_lb_ft * ONLINE_DYNO.NM_PER_LB_FT, EngineSim.DRIVE_EFFICIENCY * 100.0, normalization]
		var comparison: Dictionary = ONLINE_DYNO.compare(ONLINE_DYNO.wheel_estimate(r.curve, normalization), _online)
		if not comparison.is_empty():
			var matched: bool = comparison.power_pass and comparison.torque_pass and comparison.peak_rpm_pass and comparison.curve_pass
			_online_status.text += "\n%s · Peak error: power %+.1f%% · torque %+.1f%%" % ["WITHIN NUMERIC TARGETS" if matched else "NOT MATCHED", comparison.power_error * 100.0, comparison.torque_error * 100.0]
			if comparison.curve_power_rmse_fraction != null:
				_online_status.text += " · Curve RMS %.1f%% of peak" % (comparison.curve_power_rmse_fraction * 100.0)
	_fill(shown, wheel)


func _save_reference() -> void:
	if _reference_button.disabled:
		return
	var file := FileAccess.open(reference_path, FileAccess.WRITE)
	if file == null:
		_comparison.text = "Could not save reference run."
		return
	file.store_string(JSON.stringify({"curve": _latest_curve, "reference_id": _reference_id}))
	file.close()
	_reference = _latest_curve.duplicate(true)
	_graph.set_reference(_reference)
	_comparison.text = "Reference saved · Orange: torque · Blue: power · Grey: reference torque"


func _on_button() -> void:
	if _running:
		_running = false # so the next press reads as Close, even before the next refresh
		_button.text = "Close"
		stop_requested.emit()
	else:
		_root.visible = false


func _fill(r: Dictionary, wheel := false) -> void:
	var gears: Array = r.gears
	var has_curve: bool = not r.curve.is_empty()
	_peaks.visible = has_curve
	_grid.visible = has_curve
	_empty.visible = not has_curve
	if not has_curve:
		return
	var pt: Dictionary = r.peak_torque
	var ph: Dictionary = r.peak_hp
	var top_gear := 0
	var top_kmh := 0.0
	for g in gears:
		if float(g.kmh) > top_kmh:
			top_kmh = float(g.kmh)
			top_gear = int(g.gear)
	var top_line := ""
	if top_kmh > 0.0:
		var speed_label := "Highest road speed"
		if r.get("speed_kind", "road") == "roller":
			speed_label = "Roller speed"
		elif r.get("speed_end_reason", "") in ["plateau", "limiter"] and top_gear == gears.size():
			speed_label = "Top road speed"
		top_line = "\n%s    %.0f km/h in gear %d" % [speed_label, top_kmh, top_gear]
	var sae_line := ""
	if r.has("sae_factor") and not wheel:
		sae_line = "\nSAE J1349    %.1f hp   torque ±%.2f N·m" % [ph.corrected, pt.stdev]
	_peaks.text = "%s\nPeak torque  %.1f N·m at %s rpm\nPeak power   %.1f hp (%.1f kW) at %s rpm%s%s" % [
		"Estimated rear-wheel results (DIN)" if wheel else "Cycle-averaged crank results", pt.torque, _rpm_text(pt.rpm), ph.hp, ph.hp / HP_PER_KW, _rpm_text(ph.rpm), top_line, sae_line]
	for i in _rows.size():
		var row: Array = _rows[i]
		var shown := i < gears.size()
		for cell in row:
			cell.visible = shown
		if not shown:
			continue
		var g: Dictionary = gears[i]
		row[0].text = str(g.gear)
		if g.samples <= 0.0 or g.torque <= 0.0:
			row[1].text = "—"
			row[2].text = "—"
			row[3].text = "—"
			row[4].text = "—"
			row[5].text = "—"
		else:
			row[1].text = "%.1f" % g.torque
			row[2].text = _rpm_text(g.torque_rpm)
			row[3].text = "%.1f" % g.hp
			row[4].text = _rpm_text(g.hp_rpm)
			row[5].text = "%.0f" % g.kmh
		row[1].add_theme_color_override("font_color", TORQUE_COLOUR)
		row[3].add_theme_color_override("font_color", POWER_COLOUR)


func _load_reference() -> Array:
	if not FileAccess.file_exists(reference_path):
		return []
	var text := FileAccess.get_file_as_string(reference_path)
	var parsed = JSON.parse_string(text)
	if parsed is Array:
		return parsed if _reference_id == "" else []
	if parsed is Dictionary and parsed.has("curve"):
		return parsed.curve if str(parsed.get("reference_id", "")) == _reference_id else []
	return []


func _rpm_text(rpm: float) -> String:
	return "%d" % roundi(rpm)


func _cell(text: String, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", colour)
	label.custom_minimum_size = Vector2(52, 0)
	return label


func _style_button(b: Button) -> void:
	b.add_theme_stylebox_override("normal", _box(BUTTON, 8, 8))
	b.add_theme_stylebox_override("hover", _box(BUTTON.lightened(0.12), 8, 8))
	b.add_theme_stylebox_override("pressed", _box(ACCENT, 8, 8))


func _box(fill: Color, radius: int, margin: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	return s
