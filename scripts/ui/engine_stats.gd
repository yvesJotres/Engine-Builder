extends CanvasLayer

var _panel: PanelContainer
var _scroll: ScrollContainer
var _toggle: Button
var _engine_data: Label
var _sensors: Label
var _content: VBoxContainer


func _ready() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_panel.offset_left = -396
	_panel.offset_right = -16
	_panel.offset_top = 64
	_panel.offset_bottom = -266
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.08, 0.93)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)
	_toggle = Button.new()
	_toggle.text = "ENGINE STATS  ▾"
	_toggle.tooltip_text = "Show or hide live engine statistics"
	_toggle.pressed.connect(_toggle_stats)
	box.add_child(_toggle)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_scroll)
	var content := VBoxContainer.new()
	_content = content
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	_scroll.add_child(content)
	_engine_data = _label(content, Color(0.82, 0.84, 0.9))
	var heading := _label(content, Color(0.55, 0.75, 1.0))
	heading.text = "TEMPERATURE & MIXTURE"
	_sensors = _label(content, Color(0.75, 0.9, 0.8))
	if OS.has_feature("mobile"):
		_toggle_stats()


# Shared scroll layout owns both controls and readings, preventing overlays.
func add_controls(control: Control) -> void:
	_content.add_child(control)
	_content.move_child(control, 0)


func _label(parent: Control, colour: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", colour)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


func _toggle_stats() -> void:
	_scroll.visible = not _scroll.visible
	_toggle.text = "ENGINE STATS  ▾" if _scroll.visible else "ENGINE STATS  ▸"
	_panel.anchor_bottom = 1.0 if _scroll.visible else 0.0
	_panel.offset_bottom = -266 if _scroll.visible else 118


func set_engine_data(text: String) -> void:
	_engine_data.text = text


func set_sensors(text: String) -> void:
	_sensors.text = text
