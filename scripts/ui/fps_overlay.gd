extends CanvasLayer

# Black readout strip: frame rate, frame time, GPU time, RAM and VRAM.
# Rewritten every 250 ms so the numbers stay readable. Sits above the view, clear of the setup panel.

const REFRESH_MS := 250

var shown := false
var stats := FrameStats.new()
var label: Label
var last_write := -REFRESH_MS


func _ready() -> void:
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	layer = 3 # above the pause menu, so the readout stays up while the game is paused
	label = Label.new()
	# Top-right corner on desktop, away from the setup panel on the left; the strip grows leftward with its text.
	label.anchor_left = 1.0
	label.anchor_right = 1.0
	label.anchor_top = 0.0
	label.anchor_bottom = 0.0
	label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	label.offset_left = -16.0
	label.offset_top = 16.0
	label.offset_right = -16.0
	label.offset_bottom = 52.0
	if OS.has_feature("mobile"):
		# Below the top controls and the collapsed ENGINE STATS box (its bottom edge is 118).
		label.anchor_left = 0.0
		label.anchor_right = 1.0
		label.grow_horizontal = Control.GROW_DIRECTION_END
		label.offset_left = 372.0 # clear of the setup panel
		label.offset_right = -16.0
		label.offset_top = 124.0
		label.offset_bottom = 160.0
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color.WHITE)
	var strip := StyleBoxFlat.new()
	strip.bg_color = Color.BLACK
	strip.content_margin_left = 12.0
	strip.content_margin_right = 12.0
	strip.content_margin_top = 6.0
	label.add_theme_stylebox_override("normal", strip)
	add_child(label)


func _process(_delta: float) -> void:
	label.visible = shown
	if not shown:
		return
	var now := Time.get_ticks_msec()
	stats.tick(now)
	stats.gpu_ms = RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
	if now - last_write >= REFRESH_MS:
		last_write = now
		label.text = stats.format_line()
