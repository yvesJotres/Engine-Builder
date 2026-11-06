class_name DynoView
extends CanvasLayer

# The dyno test's screen: the dyno curve, peak torque and power, and each gear's readings. It sits on the right, so the engine
# stays in view while the test runs. Stop ends a running test; Close hides the screen once the test is over.

signal stop_requested

const BUTTON := Color(0.16, 0.17, 0.21)
const ACCENT := Color(0.25, 0.55, 0.9)
const HP_PER_KW := 1.341 # hp per kW: power in hp and kW from the same number

var _root: Control
var _status: Label
var _summary: Label
var _graph: DynoGraph
var _button: Button
var _running := false


func _ready() -> void:
	layer = 20
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE # the engine underneath keeps its clicks
	_root.visible = false
	add_child(_root)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(Color(0.06, 0.06, 0.08, 0.95), 12, 16))
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_root.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	var title := Label.new()
	title.text = "Dyno test"
	title.add_theme_font_size_override("font_size", 24)
	col.add_child(title)
	_status = Label.new()
	col.add_child(_status)
	_graph = DynoGraph.new()
	col.add_child(_graph)
	_summary = Label.new()
	_summary.add_theme_font_size_override("font_size", 16)
	col.add_child(_summary)
	_button = Button.new()
	_button.custom_minimum_size = Vector2(0, 52)
	_button.focus_mode = Control.FOCUS_NONE
	_style_button(_button)
	_button.pressed.connect(_on_button)
	col.add_child(_button)


func open() -> void:
	_root.visible = true


func is_open() -> bool:
	return _root.visible


# Shows the test as it stands: its status, the curve and the peaks so far.
func refresh(dyno: DynoTest) -> void:
	_running = dyno.active()
	_button.text = "Stop test" if _running else "Close"
	var r := dyno.result()
	_status.text = dyno.status_text()
	_status.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95) if r.ok else Color(1.0, 0.55, 0.45))
	_graph.set_curve(r.curve, dyno.redline())
	_summary.text = _summary_text(r)


func _on_button() -> void:
	if _running:
		_running = false # so the next press reads as Close, even before the next refresh
		_button.text = "Close"
		stop_requested.emit()
	else:
		_root.visible = false


func _summary_text(r: Dictionary) -> String:
	if r.curve.is_empty():
		return "No readings yet."
	var pt: Dictionary = r.peak_torque
	var ph: Dictionary = r.peak_hp
	var lines := PackedStringArray()
	lines.append("Peak torque: %.1f N·m at %s rpm" % [pt.torque, _rpm_text(pt.rpm)])
	lines.append("Peak power: %.1f hp (%.1f kW) at %s rpm" % [ph.hp, ph.hp / HP_PER_KW, _rpm_text(ph.rpm)])
	for g in r.gears:
		if g.samples <= 0.0:
			lines.append("Gear %d: not reached" % g.gear)
		elif g.torque <= 0.0:
			lines.append("Gear %d: too few readings" % g.gear)
		else:
			lines.append("Gear %d: %.1f N·m at %s rpm, %.1f hp at %s rpm" % [g.gear, g.torque, _rpm_text(g.torque_rpm), g.hp, _rpm_text(g.hp_rpm)])
	return "\n".join(lines)


func _rpm_text(rpm: float) -> String:
	return "%d" % roundi(rpm)


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
