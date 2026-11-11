class_name DynoGraph
extends Control

# Torque (left, N·m) and power (right, hp) against engine speed. The peak of each curve is marked inside the plot.

const LEFT := 56.0
const RIGHT := 48.0
const TOP := 22.0
const BOTTOM := 42.0
const TORQUE_COLOUR := Color(1.0, 0.62, 0.2)
const POWER_COLOUR := Color(0.35, 0.8, 1.0)
const TEXT_COLOUR := Color(0.78, 0.8, 0.86)
const GRID := Color(1, 1, 1, 0.1)
const FONT_SIZE := 13

var _curve: Array = []
var _reference: Array = [] # a saved curve, drawn over this one so two runs can be compared
var _reference_power := false
var _redline := 10000.0


func _init() -> void:
	custom_minimum_size = Vector2(0, 240)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL


var _t_lo := 0.0 # bottom of the zoomed torque axis, N·m
var _h_lo := 0.0 # bottom of the zoomed power axis, hp


# Position of a value between the bottom and top of an axis, 0 at the bottom and 1 at the top.
func _frac(v: float, lo: float, hi: float) -> float:
	return (v - lo) / maxf(hi - lo, 1e-6)


var _gear_pulls: Array = [] # each gear's own pull as {rpm, torque, hp} points, drawn faintly behind the combined curve


func set_curve(curve: Array, redline: float, gears: Array = [], factor := 1.0) -> void:
	_curve = curve
	_redline = redline
	_gear_pulls = []
	for g in gears:
		var pts := []
		for p in g.get("curve", []):
			pts.append({"rpm": p.rpm, "torque": float(p.torque) * factor, "hp": float(p.hp) * factor})
		_gear_pulls.append(pts)
	queue_redraw()


func set_reference(curve: Array, with_power := false) -> void:
	_reference = curve
	_reference_power = with_power
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.045, 0.06))
	var plot := Rect2(LEFT, TOP, size.x - LEFT - RIGHT, size.y - TOP - BOTTOM)
	if plot.size.x < 40.0 or plot.size.y < 40.0:
		return
	var font := get_theme_default_font()
	var rpm_scale := _scale(_redline, 2000.0 if _redline > 6000.0 else 1000.0)
	var max_rpm := rpm_scale.y
	# The axes zoom to the data, as the headless graph does, so small changes in the curve show. Zero is not forced.
	var t_min := INF
	var t_max := -INF
	var h_min := INF
	var h_max := -INF
	for p in _curve + _reference:
		t_min = minf(t_min, float(p.torque))
		t_max = maxf(t_max, float(p.torque))
		h_min = minf(h_min, float(p.hp))
		h_max = maxf(h_max, float(p.hp))
	if t_min > t_max:
		t_min = 0.0
		t_max = 1.0
	if h_min > h_max:
		h_min = 0.0
		h_max = 1.0
	var torque_step: float = _scale(t_max - t_min, 0.0).x
	var hp_step: float = _scale(h_max - h_min, 0.0).x
	_t_lo = floor(t_min / torque_step) * torque_step
	_h_lo = floor(h_min / hp_step) * hp_step
	var max_torque: float = ceil(t_max / torque_step) * torque_step
	var max_hp: float = ceil(h_max / hp_step) * hp_step
	if max_torque <= _t_lo:
		max_torque = _t_lo + torque_step
	if max_hp <= _h_lo:
		max_hp = _h_lo + hp_step
	var torque_scale := Vector2(torque_step, max_torque)
	var hp_scale := Vector2(hp_step, max_hp)

	var rpm_tick := 0.0
	while rpm_tick <= max_rpm + rpm_scale.x * 0.01:
		var x := plot.position.x + plot.size.x * rpm_tick / max_rpm
		draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), GRID)
		_centred(font, Vector2(x, plot.end.y + 16.0), "%d" % int(rpm_tick / 1000.0), TEXT_COLOUR)
		rpm_tick += rpm_scale.x
	_centred(font, Vector2(plot.position.x + plot.size.x * 0.5, size.y - 6.0), "×1000 rpm", TEXT_COLOUR)

	var torque_tick := _t_lo
	while torque_tick <= max_torque + torque_scale.x * 0.01:
		var y := plot.end.y - plot.size.y * _frac(torque_tick, _t_lo, max_torque)
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), GRID)
		draw_string(font, Vector2(2.0, y + 4.0), _tick_text(torque_tick), HORIZONTAL_ALIGNMENT_RIGHT, int(LEFT) - 8, FONT_SIZE, TORQUE_COLOUR)
		torque_tick += torque_scale.x
	var hp_tick := _h_lo
	while hp_tick <= max_hp + hp_scale.x * 0.01:
		var y := plot.end.y - plot.size.y * _frac(hp_tick, _h_lo, max_hp)
		draw_line(Vector2(plot.end.x, y), Vector2(plot.end.x + 5.0, y), Color(POWER_COLOUR, 0.8))
		draw_string(font, Vector2(plot.end.x + 8.0, y + 4.0), _tick_text(hp_tick), HORIZONTAL_ALIGNMENT_LEFT, int(RIGHT) - 10, FONT_SIZE, POWER_COLOUR)
		hp_tick += hp_scale.x
	draw_rect(plot, Color(1, 1, 1, 0.28), false, 1.0)
	draw_string(font, Vector2(2.0, 16.0), "N·m", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TORQUE_COLOUR)
	var hp_width := font.get_string_size("hp", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	draw_string(font, Vector2(size.x - hp_width - 4.0, 16.0), "hp", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, POWER_COLOUR)

	if _redline < max_rpm:
		var red_x := plot.position.x + plot.size.x * _redline / max_rpm
		draw_line(Vector2(red_x, plot.position.y), Vector2(red_x, plot.end.y), Color(0.95, 0.3, 0.25, 0.55), 1.0)
	_draw_reference(font, plot, max_rpm, max_torque, max_hp)

	if _curve.is_empty():
		_centred(font, plot.position + plot.size * 0.5, "No readings yet", TEXT_COLOUR)
		return

	var torque_runs: Array[PackedVector2Array] = []
	var power_runs: Array[PackedVector2Array] = []
	var torque_run := PackedVector2Array()
	var power_run := PackedVector2Array()
	var last_rpm := -1.0
	var peak_torque := -1.0
	var peak_hp := -1.0
	var peak_torque_at := Vector2.ZERO
	var peak_hp_at := Vector2.ZERO
	for p in _curve:
		var rpm := float(p.rpm)
		if last_rpm >= 0.0 and rpm - last_rpm > 500.0:
			torque_runs.append(torque_run)
			power_runs.append(power_run)
			torque_run = PackedVector2Array()
			power_run = PackedVector2Array()
		last_rpm = rpm
		var x := plot.position.x + plot.size.x * rpm / max_rpm
		var t_point := Vector2(x, plot.end.y - plot.size.y * clampf(_frac(float(p.torque), _t_lo, max_torque), 0.0, 1.0))
		var h_point := Vector2(x, plot.end.y - plot.size.y * clampf(_frac(float(p.hp), _h_lo, max_hp), 0.0, 1.0))
		torque_run.append(t_point)
		power_run.append(h_point)
		if float(p.torque) > peak_torque:
			peak_torque = float(p.torque)
			peak_torque_at = t_point
		if float(p.hp) > peak_hp:
			peak_hp = float(p.hp)
			peak_hp_at = h_point
	torque_runs.append(torque_run)
	power_runs.append(power_run)
	_draw_gear_pulls(plot, max_rpm, max_torque, max_hp)
	for run in torque_runs:
		_stroke(run, TORQUE_COLOUR, plot)
	for run in power_runs:
		_stroke(run, POWER_COLOUR, plot)

	var torque_text := "%.1f N·m" % peak_torque
	var power_text := "%.1f hp" % peak_hp
	var torque_box := _callout_box(font, peak_torque_at, torque_text, plot, true)
	var power_box := _callout_box(font, peak_hp_at, power_text, plot, true)
	if torque_box.intersects(power_box):
		power_box = _callout_box(font, peak_hp_at, power_text, plot, false)
	draw_circle(peak_torque_at, 4.0, TORQUE_COLOUR)
	draw_circle(peak_hp_at, 4.0, POWER_COLOUR)
	_paint_callout(font, torque_box, torque_text, TORQUE_COLOUR)
	_paint_callout(font, power_box, power_text, POWER_COLOUR)


# The saved torque curve in grey, on the same scale as the current run.
func _draw_reference(font: Font, plot: Rect2, max_rpm: float, max_torque: float, max_hp: float) -> void:
	if _reference.is_empty():
		return
	var saved := PackedVector2Array()
	var power := PackedVector2Array()
	for p in _reference:
		var x := plot.position.x + plot.size.x * float(p.rpm) / max_rpm
		saved.append(Vector2(x, plot.end.y - plot.size.y * clampf(_frac(float(p.torque), _t_lo, max_torque), 0.0, 1.0)))
		if _reference_power:
			power.append(Vector2(x, plot.end.y - plot.size.y * clampf(_frac(float(p.hp), _h_lo, max_hp), 0.0, 1.0)))
	if saved.size() >= 2:
		draw_polyline(saved, Color(0.85, 0.85, 0.9, 0.55), 1.5, true)
		for i in range(1, power.size()):
			draw_dashed_line(power[i - 1], power[i], Color(0.85, 0.85, 0.9, 0.8), 1.5, 5.0, true)
		_centred(font, Vector2(plot.position.x + 28.0, plot.position.y + 16.0), "ref", Color(0.75, 0.75, 0.8))




# Each gear's own pull, unaveraged across gears: thin lines so the spread between gears shows.
func _draw_gear_pulls(plot: Rect2, max_rpm: float, max_torque: float, max_hp: float) -> void:
	for pull in _gear_pulls:
		var torque_line := PackedVector2Array()
		var power_line := PackedVector2Array()
		for p in pull:
			var x := plot.position.x + plot.size.x * float(p.rpm) / max_rpm
			torque_line.append(Vector2(x, plot.end.y - plot.size.y * clampf(_frac(float(p.torque), _t_lo, max_torque), 0.0, 1.0)))
			power_line.append(Vector2(x, plot.end.y - plot.size.y * clampf(_frac(float(p.hp), _h_lo, max_hp), 0.0, 1.0)))
		if torque_line.size() >= 2:
			draw_polyline(torque_line, Color(TORQUE_COLOUR, 0.35), 1.0, true)
			draw_polyline(power_line, Color(POWER_COLOUR, 0.35), 1.0, true)


func _stroke(points: PackedVector2Array, colour: Color, plot: Rect2) -> void:
	if points.size() < 2:
		return
	var fill := PackedVector2Array()
	for point in points:
		fill.append(point)
	fill.append(Vector2(points[points.size() - 1].x, plot.end.y))
	fill.append(Vector2(points[0].x, plot.end.y))
	draw_colored_polygon(fill, Color(colour, 0.14))
	draw_polyline(points, colour, 2.5, true)


func _callout_box(font: Font, at: Vector2, text: String, plot: Rect2, above: bool) -> Rect2:
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	var width := text_size.x + 8.0
	var height := FONT_SIZE + 6.0
	var origin := Vector2(at.x - width * 0.5, at.y - height - 8.0 if above else at.y + 8.0)
	origin.x = clampf(origin.x, plot.position.x + 2.0, plot.end.x - width - 2.0)
	origin.y = clampf(origin.y, plot.position.y + 2.0, plot.end.y - height - 2.0)
	return Rect2(origin, Vector2(width, height))


func _paint_callout(font: Font, box: Rect2, text: String, colour: Color) -> void:
	draw_rect(box, Color(0.04, 0.045, 0.06, 0.92))
	draw_string(font, box.position + Vector2(4.0, FONT_SIZE + 1.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, colour)


func _centred(font: Font, baseline: Vector2, text: String, colour: Color) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	draw_string(font, Vector2(baseline.x - width * 0.5, baseline.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, colour)


func _tick_text(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return "%d" % int(roundf(value))
	return "%.1f" % value


# Returns (tick step, top of the scale). forced_step keeps the rpm axis on thousands; 0 picks 4 to 6 whole ticks.
func _scale(value: float, forced_step: float) -> Vector2:
	var padded := maxf(value * 1.08, 1.0)
	if forced_step > 0.0:
		return Vector2(forced_step, maxf(ceil(padded / forced_step) * forced_step, forced_step))
	var magnitude := pow(10.0, floor(log(padded) / log(10.0)))
	var best := Vector2(magnitude, ceil(padded / magnitude) * magnitude)
	for mult in [0.5, 1.0, 2.0, 2.5, 5.0]:
		var step := magnitude * float(mult)
		var top := float(ceili(padded / step)) * step
		var ticks := int(round(top / step))
		if ticks >= 4 and ticks <= 6 and top <= best.y:
			best = Vector2(step, top)
	return best
