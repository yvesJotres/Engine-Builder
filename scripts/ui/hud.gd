class_name Hud
extends CanvasLayer

# Minimal dashboard in the style of a modern sport bike TFT: a rev dial with a red redline zone,
# big speed on the right, the gear in the dial, the rpm figure under the speed, and one line of readouts.

var _panel: DashPanel
var mode := 0


func set_mode(index: int) -> void:
	mode = index
	_panel.visible = index != 2
	_panel.engine_mode = index == 1


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


func update(sim: EngineSim, spec: EngineSpec, clutch_held: bool, throttle: float = 0.0) -> void:
	var kmh := sim.speed * 3.6
	var density: float = FuelTank.PROPERTIES[sim.fuel.kind].density
	var kml := Units.km_per_litre(kmh, sim.fuel_flow, density)
	# below this fuel flow the ratio is just noise (it divides by almost nothing), so the readout shows no value
	var economy := "%.1f km/L" % minf(kml, 999.0) if kmh > 3.0 and kml > 0.0 and sim.fuel_flow > 0.05 else "-- km/L"
	var hint := "CLUTCH IN" if clutch_held else ("BRAKE" if sim.brake > 0.0 else "")
	var state := "RUNNING" if sim.running else ("CRANKING" if sim.rpm > 1.0 else "STOPPED")
	var info := "Throttle %.0f%%   O2 λ %.2f   Knocks %d" % [throttle * 100.0, sim.o2_lambda(), sim.knock_count] if mode == 1 else "%s   Fuel %.0f%%   %s" % [economy, sim.fuel.fraction() * 100.0, hint]
	_panel.set_values(sim.rpm, spec.redline_rpm, kmh, sim.gear.label(), info, state)


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
	var engine_mode := false

	func _init() -> void:
		custom_minimum_size = Vector2(640, 240)
		grow_horizontal = Control.GROW_DIRECTION_BEGIN
		grow_vertical = Control.GROW_DIRECTION_BEGIN
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func flash(text: String) -> void:
		flash_text = text
		flash_time = 2.0
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

	func _fit_font_size(font: Font, text: String, width: float, font_size: int) -> int:
		var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		return maxi(1, floori(font_size * minf(1.0, width / maxf(text_width, 1.0))))

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.045, 0.055, 0.065, 0.97))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.24, 0.28, 0.3), false, 1.0)
		draw_string(font, Vector2(20.0, 25.0), "ENGINE SPEED  /  x1000 RPM", HORIZONTAL_ALIGNMENT_LEFT, 240, 14, DIM)
		var header := flash_text if flash_time > 0.0 else top_info
		draw_string(font, Vector2(size.x - 320.0, 25.0), header, HORIZONTAL_ALIGNMENT_RIGHT, 300, _fit_font_size(font, header, 300.0, 16), Color(1.0, 0.72, 0.34) if flash_time > 0.0 else DIM)

		var max_rpm := maxf(3000.0, ceilf((redline + 1000.0) / 1000.0) * 1000.0)
		var bar_width := size.x - 40.0
		var bar := Rect2(20.0, 39.0, bar_width, 12.0)
		draw_rect(bar, Color(0.16, 0.19, 0.2))
		var red_start := clampf(redline / max_rpm, 0.0, 1.0) * bar_width
		draw_rect(Rect2(20.0 + red_start, 39.0, bar_width - red_start, 12.0), Color(0.35, 0.15, 0.13))
		var filled := clampf(rpm / max_rpm, 0.0, 1.0) * bar_width
		if filled > 0.0:
			draw_rect(Rect2(20.0, 39.0, minf(filled, red_start), 12.0), Color(0.48, 0.82, 0.72))
			if filled > red_start:
				draw_rect(Rect2(20.0 + red_start, 39.0, filled - red_start, 12.0), RED)
		var tick_step := 2000.0 if max_rpm <= 16000.0 else 4000.0
		var tick := 0.0
		while tick <= max_rpm:
			var tick_x := 20.0 + tick / max_rpm * bar_width
			draw_line(Vector2(tick_x, 54.0), Vector2(tick_x, 58.0), DIM, 1.0)
			draw_string(font, Vector2(clampf(tick_x - 14.0, 20.0, size.x - 48.0), 73.0), str(roundi(tick / 1000.0)), HORIZONTAL_ALIGNMENT_CENTER, 28, 12, DIM)
			tick += tick_step

		draw_string(font, Vector2(24.0, 102.0), "GEAR", HORIZONTAL_ALIGNMENT_LEFT, 100, 14, DIM)
		draw_string(font, Vector2(24.0, 176.0), gear, HORIZONTAL_ALIGNMENT_LEFT, 100, 68, GREEN if gear == "N" else TEXT)
		draw_line(Vector2(135.0, 90.0), Vector2(135.0, 182.0), Color(0.24, 0.28, 0.3), 1.0)
		draw_string(font, Vector2(158.0, 102.0), "REDLINE" if engine_mode else "SPEED", HORIZONTAL_ALIGNMENT_LEFT, 160, 14, DIM)
		var speed_text := str(roundi(redline if engine_mode else speed))
		draw_string(font, Vector2(158.0, 176.0), speed_text, HORIZONTAL_ALIGNMENT_LEFT, 140, _fit_font_size(font, speed_text, 140.0, 68), TEXT)
		draw_string(font, Vector2(310.0, 176.0), "rpm" if engine_mode else "km/h", HORIZONTAL_ALIGNMENT_LEFT, 70, 18, DIM)
		draw_line(Vector2(390.0, 90.0), Vector2(390.0, 182.0), Color(0.24, 0.28, 0.3), 1.0)
		draw_string(font, Vector2(414.0, 102.0), "RPM", HORIZONTAL_ALIGNMENT_LEFT, 160, 14, DIM)
		var rpm_text := str(roundi(rpm))
		draw_string(font, Vector2(414.0, 160.0), rpm_text, HORIZONTAL_ALIGNMENT_LEFT, size.x - 434.0, _fit_font_size(font, rpm_text, size.x - 434.0, 40), RED if rpm >= redline else TEXT)
		draw_line(Vector2(20.0, size.y - 42.0), Vector2(size.x - 20.0, size.y - 42.0), Color(0.24, 0.28, 0.3), 1.0)
		draw_string(font, Vector2(24.0, size.y - 15.0), info, HORIZONTAL_ALIGNMENT_LEFT, size.x - 48.0, 16, DIM)
