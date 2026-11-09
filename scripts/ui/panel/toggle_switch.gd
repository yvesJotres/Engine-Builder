class_name ToggleSwitch
extends Control

# An on/off switch for the control panel: a pill with a sliding knob and its state written beside it. It keeps the dropdown's
# interface, so the panel's code does not change: selected is 0 (Off) or 1 (On), select() changes it without a signal, and
# item_selected fires when the rider taps it.

signal item_selected(index: int)

const TRACK_W := 46.0
const TRACK_H := 24.0
const KNOB_INSET := 3.0
const TRACK_OFF := Color(0.24, 0.26, 0.31)
const TRACK_ON := Color(0.25, 0.55, 0.9)
const KNOB := Color(0.95, 0.96, 0.98)
const TEXT_ON := Color(0.92, 0.94, 0.97)
const TEXT_OFF := Color(0.6, 0.63, 0.7)
const TEXT_SIZE := 16

var _items: Array[String] = []
var _selected := 0


var selected: int:
	get:
		return _selected
	set(value):
		_selected = clampi(value, 0, maxi(_items.size() - 1, 0))
		queue_redraw()


var item_count: int:
	get:
		return _items.size()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(TRACK_W + 80.0, TRACK_H + 12.0)


func add_item(text: String) -> void:
	_items.append(text)
	queue_redraw()


func get_item_text(index: int) -> String:
	return _items[index] if index >= 0 and index < _items.size() else ""


func select(index: int) -> void:
	selected = index


func _gui_input(event: InputEvent) -> void:
	# Taps reach here as mouse events too (touch is emulated as mouse), so only the mouse button and the accept key count.
	var tapped: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	if tapped or event.is_action_pressed("ui_accept"):
		_toggle()
		accept_event()


func _toggle() -> void:
	if _items.size() < 2:
		return
	selected = (_selected + 1) % _items.size()
	item_selected.emit(_selected)


func _draw() -> void:
	var on := _selected == 1
	var top := (size.y - TRACK_H) * 0.5
	var track := StyleBoxFlat.new()
	track.bg_color = TRACK_ON if on else TRACK_OFF
	track.set_corner_radius_all(int(TRACK_H * 0.5))
	draw_style_box(track, Rect2(0.0, top, TRACK_W, TRACK_H))
	var knob_r := TRACK_H * 0.5 - KNOB_INSET
	var knob_x := TRACK_W - KNOB_INSET - knob_r if on else KNOB_INSET + knob_r
	draw_circle(Vector2(knob_x, size.y * 0.5), knob_r, KNOB)
	var text := get_item_text(_selected)
	var colour := TEXT_ON if on else TEXT_OFF
	draw_string(get_theme_default_font(), Vector2(TRACK_W + 10.0, size.y * 0.5 + TEXT_SIZE * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE, colour)
	if has_focus():
		draw_rect(Rect2(Vector2.ZERO, size), TRACK_ON, false, 1.0)
