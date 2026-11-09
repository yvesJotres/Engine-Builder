class_name PauseMenu
extends CanvasLayer

# Pause overlay: Resume, Options (graphics quality, fullscreen) and Quit.
# It only reports choices through signals; main.gd decides what they change.

signal resume_requested
signal quality_changed(index: int) # 0 = Low, 1 = High
signal accuracy_changed(index: int) # index into PHYSICS_RATES
const PHYSICS_RATES := [1200, 2400, 3600, 7200] # physics steps per second the player can choose from
signal blur_toggled(on: bool) # frame blend motion blur, off by default
signal sound_toggled(on: bool) # the engine sound, on or off
signal fps_toggled(on: bool) # the frame-rate strip, on by default
signal hud_changed(index: int)

var settings_path := "user://settings.cfg"
var _settings := ConfigFile.new()
var _quality: OptionButton
var _accuracy: OptionButton
var _blur_box: CheckBox
var _fps_box: CheckBox
var _hud_mode: OptionButton

func _setting(key: String, fallback: Variant) -> Variant:
	var value: Variant = _settings.get_value("options", key, fallback)
	return value if typeof(value) == typeof(fallback) else fallback


func _save_setting(key: String, value: Variant) -> void:
	_settings.set_value("options", key, value)
	var err := _settings.save(settings_path)
	if err != OK:
		push_warning("Could not save settings: error %d" % err)


func _ready() -> void:
	_settings.load(settings_path)
	visible = false
	layer = 2 # above the touch pads (layer 1), so the menu is not cut across by them
	# dims the scene and the pads behind the menu. It stops taps, so nothing below it (pads, settings panel, 3D view) can be touched
	# while paused; the menu's own buttons sit above it and still work. Resume, Esc or Space carry on.
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(scroll)
	var centre := CenterContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.size_flags_vertical = Control.SIZE_EXPAND_FILL
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(centre)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 0)
	panel.add_theme_stylebox_override("panel", _box(Color(0.06, 0.06, 0.08, 0.96), 16, 24))
	centre.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	box.add_child(title)
	var hint := Label.new()
	hint.text = "Tap Resume to continue" if OS.has_feature("mobile") else "Esc or Space to carry on"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.66))
	box.add_child(hint)

	var resume := _button("Resume", box, Color(0.25, 0.55, 0.9))
	resume.pressed.connect(func() -> void: resume_requested.emit())

	var options := _button("Options", box, Color(0.16, 0.17, 0.21))
	var options_box := VBoxContainer.new()
	options_box.visible = false
	options_box.add_theme_constant_override("separation", 10)
	box.add_child(options_box)
	options.pressed.connect(func() -> void: options_box.visible = not options_box.visible)

	var quality_label := Label.new()
	quality_label.text = "Graphics quality"
	options_box.add_child(quality_label)
	var quality := OptionButton.new()
	quality.add_item("Low")
	quality.add_item("High")
	quality.custom_minimum_size = Vector2(0, 48)
	quality.select(clampi(_setting("quality", 0 if OS.has_feature("mobile") else 1), 0, 1))
	quality.focus_mode = Control.FOCUS_NONE
	quality.item_selected.connect(func(i: int) -> void:
		_save_setting("quality", i)
		quality_changed.emit(i))
	options_box.add_child(quality)
	_quality = quality

	var accuracy_label := Label.new()
	accuracy_label.text = "Physics steps per second"
	options_box.add_child(accuracy_label)
	var accuracy := OptionButton.new()
	for rate in PHYSICS_RATES:
		var suffix := "  (fast)" if rate == 1200 else ("  (balanced, recommended)" if rate == 2400 else ("  (accurate)" if rate == 3600 else "  (ultra, slow)"))
		accuracy.add_item("%s steps a second%s" % [rate, suffix])
	accuracy.custom_minimum_size = Vector2(0, 48)
	accuracy.select(clampi(_setting("accuracy", 1), 0, PHYSICS_RATES.size() - 1))
	accuracy.focus_mode = Control.FOCUS_NONE
	accuracy.item_selected.connect(func(i: int) -> void:
		_save_setting("accuracy", i)
		accuracy_changed.emit(i))
	options_box.add_child(accuracy)
	_accuracy = accuracy

	var fullscreen := CheckBox.new()
	fullscreen.text = "Fullscreen (F11)"
	fullscreen.custom_minimum_size = Vector2(0, 40)
	fullscreen.button_pressed = _setting("fullscreen", DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN)
	fullscreen.focus_mode = Control.FOCUS_NONE
	fullscreen.toggled.connect(func(on: bool) -> void:
		_save_setting("fullscreen", on)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED))
	if not OS.has_feature("mobile"):
		options_box.add_child(fullscreen)
	_fullscreen_box = fullscreen

	var blur := CheckBox.new()
	blur.text = "Motion blur (costs frame rate)"
	blur.custom_minimum_size = Vector2(0, 40)
	blur.button_pressed = _setting("blur", false) if not OS.has_feature("mobile") else false
	blur.focus_mode = Control.FOCUS_NONE
	blur.toggled.connect(func(on: bool) -> void:
		_save_setting("blur", on)
		blur_toggled.emit(on))
	if not OS.has_feature("mobile"): # on the phone's Compatibility renderer the 3D view goes blank with blur on, so it is hidden there
		options_box.add_child(blur)
	_blur_box = blur

	var sound := CheckBox.new()
	sound.text = "Sound"
	sound.custom_minimum_size = Vector2(0, 40)
	sound.button_pressed = _setting("sound", true)
	sound.focus_mode = Control.FOCUS_NONE
	sound.toggled.connect(func(on: bool) -> void:
		_save_setting("sound", on)
		sound_toggled.emit(on))
	options_box.add_child(sound)
	_sound_box = sound

	var fps := CheckBox.new()
	fps.text = "Show FPS"
	fps.custom_minimum_size = Vector2(0, 40)
	fps.button_pressed = _setting("fps", false)
	fps.focus_mode = Control.FOCUS_NONE
	fps.toggled.connect(func(on: bool) -> void:
		_save_setting("fps", on)
		fps_toggled.emit(on))
	options_box.add_child(fps)
	_fps_box = fps

	var hud_label := Label.new()
	hud_label.text = "Dashboard"
	options_box.add_child(hud_label)
	_hud_mode = OptionButton.new()
	for mode in ["Drive", "Engine", "Hidden"]:
		_hud_mode.add_item(mode)
	_hud_mode.select(clampi(_setting("hud_mode", 0), 0, 2))
	_hud_mode.item_selected.connect(func(i: int) -> void:
		_save_setting("hud_mode", i)
		hud_changed.emit(i))
	options_box.add_child(_hud_mode)

	# Quit takes two taps, so one stray tap cannot end the session
	var quit := _button("Quit", box, Color(0.45, 0.16, 0.16))
	quit.pressed.connect(_on_quit_pressed.bind(quit))


# Tall buttons so they are easy to tap on a phone; the accent colour marks the main choice.
# Keeps the fullscreen checkbox in step with F11, without sending the signal back.
func set_fullscreen_checked(on: bool) -> void:
	if _fullscreen_box:
		_fullscreen_box.set_pressed_no_signal(on)
		_save_setting("fullscreen", on)


func _on_quit_pressed(button: Button) -> void:
	if not _quit_armed:
		_quit_armed = true
		button.text = "Tap again to quit"
		return
	get_tree().quit()


var _fullscreen_box: CheckBox
var _quit_armed := false


# Keeps the checkbox in step with the Sound button and M, without sending the signal back.
func set_sound_checked(on: bool) -> void:
	if _sound_box:
		_sound_box.set_pressed_no_signal(on)
		_save_setting("sound", on)


func apply_settings() -> void:
	quality_changed.emit(_quality.selected)
	accuracy_changed.emit(_accuracy.selected)
	blur_toggled.emit(_blur_box.button_pressed)
	sound_toggled.emit(_sound_box.button_pressed)
	fps_toggled.emit(_fps_box.button_pressed)
	hud_changed.emit(_hud_mode.selected)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if _fullscreen_box.button_pressed else DisplayServer.WINDOW_MODE_WINDOWED)


var _sound_box: CheckBox


func _button(text: String, parent: Control, fill: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 56)
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_stylebox_override("normal", _box(fill, 10, 10))
	b.add_theme_stylebox_override("hover", _box(fill.lightened(0.15), 10, 10))
	b.add_theme_stylebox_override("pressed", _box(fill.darkened(0.2), 10, 10))
	b.focus_mode = Control.FOCUS_NONE # keeps Space from pressing the focused button
	parent.add_child(b)
	return b


func _box(fill: Color, radius: int, margin: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	return s
