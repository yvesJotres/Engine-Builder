class_name IgnitionKnob
extends Control

# Click to switch the ignition on or off. The pointer turns from the OFF to the ON position.
signal toggled(on: bool)

var on := false


func _init() -> void:
	custom_minimum_size = Vector2(72, 72)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		on = not on
		toggled.emit(on)
		queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.45
	draw_circle(c, r + 4.0, Color(0.3, 0.3, 0.33))
	draw_circle(c, r, Color(0.12, 0.12, 0.14))
	var angle := deg_to_rad(135.0 if on else -135.0) # clockwise from straight up
	var dir := Vector2(sin(angle), -cos(angle))
	draw_line(c, c + dir * r * 0.8, Color(0.3, 0.9, 0.4) if on else Color(0.9, 0.35, 0.3), 4.0)
