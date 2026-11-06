class_name DynoGraph
extends Control

# The dyno curve: torque (left axis, N·m) and power (right axis, hp) against rpm, with the peak of each marked.

const LEFT := 58.0
const RIGHT := 58.0
const TOP := 34.0
const BOTTOM := 36.0
const TORQUE_COLOUR := Color(1.0, 0.62, 0.2)
const POWER_COLOUR := Color(0.35, 0.8, 1.0)
const TEXT_COLOUR := Color(0.8, 0.82, 0.88)
const FONT_SIZE := 14

var _curve: Array = []
var _redline := 10000.0


func _init() -> void:
	custom_minimum_size = Vector2(560, 340)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func set_curve(curve: Array, redline: float) -> void:
	_curve = curve
	_redline = redline
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.03, 0.05))
	var plot := Rect2(LEFT, TOP, size.x - LEFT - RIGHT, size.y - TOP - BOTTOM)
	if plot.size.x < 40.0 or plot.size.y < 40.0:
		return
	var font := get_theme_default_font()
	var max_rpm := ceilf(_redline / 1000.0) * 1000.0
	var max_torque := 10.0
	var max_hp := 10.0
	for p in _curve:
		max_torque = maxf(max_torque, float(p.torque))
		max_hp = maxf(max_hp, float(p.hp))
	max_torque = ceilf(max_torque * 1.1 / 5.0) * 5.0
	max_hp = ceilf(max_hp * 1.1 / 5.0) * 5.0

	# grid: a line every 1,000 rpm, and five steps on each axis
	for rpm in range(0, int(max_rpm) + 1, 1000):
		var x := plot.position.x + plot.size.x * rpm / max_rpm
		draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), Color(1, 1, 1, 0.08))
		draw_string(font, Vector2(x - 14.0, plot.end.y + 24.0), "%dk" % (rpm / 1000), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT_COLOUR)
	for i in 5:
		var y := plot.end.y - plot.size.y * i / 4.0
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), Color(1, 1, 1, 0.08))
		draw_string(font, Vector2(4.0, y + 5.0), "%d" % roundi(max_torque * i / 4.0), HORIZONTAL_ALIGNMENT_LEFT, int(LEFT) - 10, FONT_SIZE, TORQUE_COLOUR)
		draw_string(font, Vector2(plot.end.x + 6.0, y + 5.0), "%d" % roundi(max_hp * i / 4.0), HORIZONTAL_ALIGNMENT_LEFT, int(RIGHT) - 6, FONT_SIZE, POWER_COLOUR)
	draw_rect(plot, Color(1, 1, 1, 0.2), false, 1.0)
	draw_string(font, Vector2(4.0, 20.0), "N·m", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TORQUE_COLOUR)
	draw_string(font, Vector2(plot.end.x + 6.0, 20.0), "hp", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, POWER_COLOUR)
	draw_string(font, Vector2(plot.end.x - 40.0, size.y - 8.0), "rpm", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT_COLOUR)

	if _curve.is_empty():
		return
	var torque_pts := PackedVector2Array()
	var power_pts := PackedVector2Array()
	var peak_torque := -1.0
	var peak_hp := -1.0
	var peak_torque_at := Vector2.ZERO
	var peak_hp_at := Vector2.ZERO
	for p in _curve:
		var x := plot.position.x + plot.size.x * float(p.rpm) / max_rpm
		var t_point := Vector2(x, plot.end.y - plot.size.y * float(p.torque) / max_torque)
		var h_point := Vector2(x, plot.end.y - plot.size.y * float(p.hp) / max_hp)
		torque_pts.append(t_point)
		power_pts.append(h_point)
		if float(p.torque) > peak_torque:
			peak_torque = float(p.torque)
			peak_torque_at = t_point
		if float(p.hp) > peak_hp:
			peak_hp = float(p.hp)
			peak_hp_at = h_point
	if torque_pts.size() >= 2:
		draw_polyline(torque_pts, TORQUE_COLOUR, 3.0, true)
		draw_polyline(power_pts, POWER_COLOUR, 3.0, true)
	# the peaks, marked and labelled
	draw_circle(peak_torque_at, 5.0, TORQUE_COLOUR)
	draw_string(font, peak_torque_at + Vector2(-60.0, -12.0), "%.1f N·m" % peak_torque, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TORQUE_COLOUR)
	draw_circle(peak_hp_at, 5.0, POWER_COLOUR)
	draw_string(font, peak_hp_at + Vector2(-30.0, -12.0), "%.1f hp" % peak_hp, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, POWER_COLOUR)
