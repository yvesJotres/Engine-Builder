class_name CompressorMapView
extends Control

# Real-time compressor map visualizer showing speed lines, surge/choke boundaries, and current operating point.

@export var map: CompressorMap = null
@export var current_corrected_flow: float = 0.0
@export var current_pr: float = 1.0
@export var current_corrected_speed: float = 0.0

const MARGIN := 40.0
const PLOT_SIZE := 250.0

func _draw() -> void:
	if map == null or map.speed_lines.is_empty():
		return
	
	var view = get_rect().size
	var plot_w = min(view.x - 2 * MARGIN, PLOT_SIZE)
	var plot_h = min(view.y - 2 * MARGIN, PLOT_SIZE)
	var origin = Vector2(MARGIN, view.y - MARGIN)
	
	# Axes
	draw_line(origin, origin + Vector2(plot_w, 0.0), Color(0.5, 0.5, 0.55), 1.0)
	draw_line(origin, origin + Vector2(0.0, -plot_h), Color(0.5, 0.5, 0.55), 1.0)
	
	# Labels
	var font = get_theme_font("font", "Label")
	draw_string(font, origin + Vector2(plot_w * 0.5 - 40, 20), "Corrected Mass Flow (kg/s)", HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Color(0.8, 0.8, 0.85))
	draw_string(font, origin + Vector2(-120, -plot_h * 0.5), "Pressure Ratio", HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Color(0.8, 0.8, 0.85), PI / 2.0)
	
	# Determine axis ranges from map data
	var min_flow = INF
	var max_flow = -INF
	var min_pr = INF
	var max_pr = -INF
	
	for line in map.speed_lines:
		for pt in line[1]:
			min_flow = min(min_flow, pt[1])
			max_flow = max(max_flow, pt[1])
			min_pr = min(min_pr, pt[0])
			max_pr = max(max_pr, pt[0])
	for pt in map.surge_line:
		min_flow = min(min_flow, pt[0])
		max_flow = max(max_flow, pt[0])
		min_pr = min(min_pr, pt[1])
		max_pr = max(max_pr, pt[1])
	for pt in map.choke_line:
		min_flow = min(min_flow, pt[0])
		max_flow = max(max_flow, pt[0])
		min_pr = min(min_pr, pt[1])
		max_pr = max(max_pr, pt[1])
	
	# Add padding
	var flow_range = max_flow - min_flow
	var pr_range = max_pr - min_pr
	min_flow -= flow_range * 0.05
	max_flow += flow_range * 0.05
	min_pr -= pr_range * 0.05
	max_pr += pr_range * 0.05
	
	# Grid lines
	for i in range(6):
		var f = lerp(min_flow, max_flow, i / 5.0)
		var x = origin.x + (f - min_flow) / (max_flow - min_flow) * plot_w
		draw_line(Vector2(x, origin.y), Vector2(x, origin.y - plot_h), Color(0.2, 0.2, 0.25), 0.5, true)
		draw_string(font, Vector2(x - 15, origin.y + 4), "%.2f" % f, HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color(0.6, 0.6, 0.65))
	
	for i in range(6):
		var p = lerp(min_pr, max_pr, i / 5.0)
		var y = origin.y - (p - min_pr) / (max_pr - min_pr) * plot_h
		draw_line(Vector2(origin.x, y), Vector2(origin.x + plot_w, y), Color(0.2, 0.2, 0.25), 0.5, true)
		draw_string(font, Vector2(origin.x - 55, y + 4), "%.1f" % p, HORIZONTAL_ALIGNMENT_RIGHT, -1, 10, Color(0.6, 0.6, 0.65))
	
	# Speed lines
	for line_idx in map.speed_lines.size():
		var line = map.speed_lines[line_idx]
		var pts = line[1]
		pts.sort_custom(func(a, b): return a[1] < b[1])
		
		var col = Color(0.3, 0.6, 1.0, 0.8)
		var prev = _map_point(pts[0][1], pts[0][0], origin, plot_w, plot_h, min_flow, max_flow, min_pr, max_pr)
		for i in range(1, pts.size()):
			var curr = _map_point(pts[i][1], pts[i][0], origin, plot_w, plot_h, min_flow, max_flow, min_pr, max_pr)
			draw_line(prev, curr, col, 2.0)
			prev = curr
		
		# Label speed line
		var label_pt = _map_point(pts[-1][1], pts[-1][0], origin, plot_w, plot_h, min_flow, max_flow, min_pr, max_pr)
		draw_string(font, label_pt + Vector2(5, 4), "%d rpm" % line[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
	
	# Surge line (red, dashed)
	if map.surge_line.size() >= 2:
		var prev = _map_point(map.surge_line[0][0], map.surge_line[0][1], origin, plot_w, plot_h, min_flow, max_flow, min_pr, max_pr)
		for i in range(1, map.surge_line.size()):
			var curr = _map_point(map.surge_line[i][0], map.surge_line[i][1], origin, plot_w, plot_h, min_flow, max_flow, min_pr, max_pr)
			draw_line(prev, curr, Color(1.0, 0.3, 0.3), 2.0, true)
			prev = curr
		draw_string(font, prev + Vector2(5, 4), "Surge", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.3, 0.3))
	
	# Choke line (orange, dashed)
	if map.choke_line.size() >= 2:
		var prev = _map_point(map.choke_line[0][0], map.choke_line[0][1], origin, plot_w, plot_h, min_flow, max_flow, min_pr, max_pr)
		for i in range(1, map.choke_line.size()):
			var curr = _map_point(map.choke_line[i][0], map.choke_line[i][1], origin, plot_w, plot_h, min_flow, max_flow, min_pr, max_pr)
			draw_line(prev, curr, Color(1.0, 0.6, 0.2), 2.0, true)
			prev = curr
		draw_string(font, prev + Vector2(5, 4), "Choke", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.6, 0.2))
	
	# Current operating point
	if current_corrected_flow > 0.0 and current_pr > 1.0:
		var pt = _map_point(current_corrected_flow, current_pr, origin, plot_w, plot_h, min_flow, max_flow, min_pr, max_pr)
		# Crosshair
		draw_line(pt + Vector2(-8, 0), pt + Vector2(8, 0), Color(0.2, 1.0, 0.4), 2.0)
		draw_line(pt + Vector2(0, -8), pt + Vector2(0, 8), Color(0.2, 1.0, 0.4), 2.0)
		draw_circle(pt, 6.0, Color(0.2, 1.0, 0.4, 0.3))
		draw_string(font, pt + Vector2(10, -10), "Flow: %.3f\nPR: %.2f\nSpeed: %.0f rpm" % [current_corrected_flow, current_pr, current_corrected_speed], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.2, 1.0, 0.4))

func _map_point(flow: float, pr: float, origin: Vector2, plot_w: float, plot_h: float, min_flow: float, max_flow: float, min_pr: float, max_pr: float) -> Vector2:
	var x = origin.x + clamp((flow - min_flow) / (max_flow - min_flow), 0.0, 1.0) * plot_w
	var y = origin.y - clamp((pr - min_pr) / (max_pr - min_pr), 0.0, 1.0) * plot_h
	return Vector2(x, y)


func set_operating_point(corrected_flow: float, pr: float, corrected_speed: float) -> void:
	current_corrected_flow = corrected_flow
	current_pr = pr
	current_corrected_speed = corrected_speed
	queue_redraw()