class_name Hud
extends CanvasLayer

# Minimal dashboard in the style of a modern sport bike TFT: a rev dial with a red redline zone,
# big speed on the right, the gear in the dial, the rpm figure under the speed, and one line of readouts.

var _panel: DashPanel


func _ready() -> void:
	_panel = DashPanel.new()
	_panel.anchor_left = 1.0
	_panel.anchor_top = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -640.0
	_panel.offset_top = -250.0
	_panel.offset_right = -16.0
	_panel.offset_bottom = -16.0
	add_child(_panel)


# Refreshes every readout from the bike state. Called once per frame.
func flash(text: String) -> void:
	_panel.flash(text)


func update(sim: EngineSim, spec: EngineSpec, clutch_held: bool) -> void:
	var kmh := sim.speed * 3.6
	var density: float = FuelTank.PROPERTIES[sim.fuel.kind].density
	var kml := Units.km_per_litre(kmh, sim.fuel_flow, density)
	var economy := "%.1f km/L" % kml if kmh > 3.0 and kml > 0.0 else "-- km/L"
	var hint := "Clutch in" if clutch_held else ("Brake (B)" if sim.brake > 0.0 else "Shift+Q/E to shift")
	var clock := Time.get_time_dict_from_system()
	var air := "Air %.0f °C" % Units.k_to_c(EngineAir.T0)
	_panel.set_values(sim.rpm, spec.redline_rpm, kmh, sim.gear.label(), "%s   %s" % [economy, hint],
		"%02d:%02d   %s" % [clock.hour, clock.minute, air])


# The dashboard itself: everything is drawn here, so it stays crisp at any window size.
class DashPanel extends Control:
	const TEXT := Color(0.97, 0.97, 0.99)
	const DIM := Color(0.78, 0.78, 0.84)
	const RED := Color(0.95, 0.25, 0.2)
	const GREEN := Color(0.35, 0.95, 0.45)

	var rpm := 0.0
	var redline := 10000.0
	var speed := 0.0
	var gear := "N"
	var info := ""
	var top_info := ""
	var flash_text := ""
	var flash_time := 0.0 # seconds left to show the shift message

	func _init() -> void:
		custom_minimum_size = Vector2(640, 240)
		grow_horizontal = Control.GROW_DIRECTION_BEGIN
		grow_vertical = Control.GROW_DIRECTION_BEGIN

	func flash(text: String) -> void:
		flash_text = text
		flash_time = 0.9
		queue_redraw()

	func _process(delta: float) -> void:
		if flash_time > 0.0:
			flash_time = maxf(flash_time - delta, 0.0)
			queue_redraw()

	func set_values(new_rpm: float, new_redline: float, new_speed: float, new_gear: String, new_info: String, new_top: String) -> void:
		rpm = new_rpm
		redline = new_redline
		speed = new_speed
		gear = new_gear
		info = new_info
		top_info = new_top
		queue_redraw()

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.04, 0.05, 0.96))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.25, 0.25, 0.3), false, 2.0)

		# rev dial: a semicircle with ticks every 1,000 rpm and a red zone above the redline.
		# Scale runs to the redline rounded up, plus a little more, and never below 12,000 rpm.
		var max_rpm := maxf(12000.0, ceilf((redline + 1000.0) / 1000.0) * 1000.0)
		var centre := Vector2(size.x * 0.5, size.y * 0.74)
		var radius := size.y * 0.6
		var arc_start := PI
		var arc_end := TAU
		draw_arc(centre, radius, arc_start, arc_end, 96, DIM, 3.0)
		var redline_frac := clampf(redline / max_rpm, 0.0, 1.0)
		draw_arc(centre, radius, arc_start + redline_frac * PI, arc_end, 48, RED, 8.0)
		var tick := 0.0
		while tick <= max_rpm:
			var a := arc_start + PI * tick / max_rpm
			var dir := Vector2.from_angle(a)
			draw_line(centre + dir * (radius - 12.0), centre + dir * radius, DIM, 2.0)
			draw_string(font, centre + dir * (radius - 32.0) + Vector2(-20.0, 6.0), str(roundi(tick / 1000.0)), HORIZONTAL_ALIGNMENT_CENTER, 40, 18, DIM)
			tick += 1000.0
		var needle := Vector2.from_angle(arc_start + PI * clampf(rpm / max_rpm, 0.0, 1.0))
		draw_line(centre, centre + needle * (radius - 8.0), RED, 5.0)
		draw_circle(centre, 7.0, DIM)

		# gear in a green ring at the centre of the dial
		var ring_centre := centre + Vector2.from_angle(PI * 1.5) * radius * 0.4
		draw_circle(ring_centre, size.y * 0.15, Color(0.08, 0.08, 0.1))
		draw_arc(ring_centre, size.y * 0.15, 0.0, TAU, 48, GREEN, 3.0)
		draw_string(font, ring_centre + Vector2(-size.y * 0.15, size.y * 0.12), gear, HORIZONTAL_ALIGNMENT_CENTER, size.y * 0.3, 56, GREEN)

		# speed on the right, rpm figure under it
		draw_string(font, Vector2(size.x - 226.0, size.y * 0.6), str(roundi(speed)), HORIZONTAL_ALIGNMENT_RIGHT, 210, 104, TEXT)
		draw_string(font, Vector2(size.x - 226.0, size.y * 0.72), "km/h", HORIZONTAL_ALIGNMENT_RIGHT, 210, 22, DIM)
		draw_string(font, Vector2(size.x - 226.0, size.y * 0.86), "%d rpm" % roundi(rpm), HORIZONTAL_ALIGNMENT_RIGHT, 210, 20, RED if rpm >= redline else DIM)

		# gear column on the left: neutral lamp on top, the selected gear lit
		var current := 0 if gear == "N" else gear.to_int()
		draw_circle(Vector2(30.0, 30.0), 9.0, GREEN if current == 0 else Color(0.15, 0.3, 0.18))
		for g in range(1, 7):
			var box := Rect2(14.0, 46.0 + (g - 1) * 26.0, 40.0, 22.0)
			draw_rect(box, TEXT if g == current else Color(0.15, 0.15, 0.18))
			draw_string(font, box.position + Vector2(0.0, 16.0), str(g), HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 16, Color(0.05, 0.05, 0.06) if g == current else DIM)

		# top-left: clock and air temperature
		draw_string(font, Vector2(60.0, 32.0), top_info, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, DIM)

		# shift message, fading out over the last part of its time
		if flash_time > 0.0:
			var alpha := clampf(flash_time / 0.3, 0.0, 1.0)
			draw_string(font, Vector2(size.x * 0.5 - 120.0, 32.0), flash_text, HORIZONTAL_ALIGNMENT_CENTER, 240, 22, Color(1.0, 0.8, 0.3, alpha))

		# one line of readouts along the bottom
		# starts right of the gear column so the two never overlap
		draw_string(font, Vector2(66.0, size.y - 12.0), info, HORIZONTAL_ALIGNMENT_LEFT, size.x - 82.0, 18, DIM)
