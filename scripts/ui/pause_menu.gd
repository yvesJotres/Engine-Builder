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


func _ready() -> void:
	visible = false
	layer = 2 # above the touch pads (layer 1), so the menu is not cut across by them
	# dims the scene and the pads behind the menu; the full-screen layers ignore the mouse, so taps still reach
	# the PAUSE pad and the panel alone takes input
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
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
	hint.text = "Esc or Space to carry on"
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
	quality.select(0 if OS.has_feature("mobile") else 1) # High on a PC, Low on a phone, as main.gd starts
	quality.focus_mode = Control.FOCUS_NONE
	quality.item_selected.connect(func(i: int) -> void: quality_changed.emit(i))
	options_box.add_child(quality)

	var accuracy_label := Label.new()
	accuracy_label.text = "Physics steps per second"
	options_box.add_child(accuracy_label)
	var accuracy := OptionButton.new()
	for rate in PHYSICS_RATES:
		accuracy.add_item("%s steps a second" % rate + ("  (may run away on 4-cylinder engines)" if rate < 3600 else ("  (recommended)" if rate == 3600 else "  (slower)")))
	accuracy.custom_minimum_size = Vector2(0, 48)
	accuracy.select(2) # 3,600 steps a second on every device, the setting the 4-cylinder engines need
	accuracy.focus_mode = Control.FOCUS_NONE
	accuracy.item_selected.connect(func(i: int) -> void: accuracy_changed.emit(i))
	options_box.add_child(accuracy)

	var fullscreen := CheckBox.new()
	fullscreen.text = "Fullscreen (F11)"
	fullscreen.custom_minimum_size = Vector2(0, 40)
	fullscreen.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fullscreen.focus_mode = Control.FOCUS_NONE
	fullscreen.toggled.connect(func(on: bool) -> void:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED))
	options_box.add_child(fullscreen)
	_fullscreen_box = fullscreen

	var blur := CheckBox.new()
	blur.text = "Motion blur (costs frame rate)"
	blur.custom_minimum_size = Vector2(0, 40)
	blur.button_pressed = false
	blur.focus_mode = Control.FOCUS_NONE
	blur.toggled.connect(func(on: bool) -> void: blur_toggled.emit(on))
	if not OS.has_feature("mobile"): # on the phone's Compatibility renderer the 3D view goes blank with blur on, so it is hidden there
		options_box.add_child(blur)

	var sound := CheckBox.new()
	sound.text = "Sound"
	sound.custom_minimum_size = Vector2(0, 40)
	sound.button_pressed = true # on by default, as the control panel starts
	sound.focus_mode = Control.FOCUS_NONE
	sound.toggled.connect(func(on: bool) -> void: sound_toggled.emit(on))
	options_box.add_child(sound)
	_sound_box = sound

	# Quit takes two taps, so one stray tap cannot end the session
	var quit := _button("Quit", box, Color(0.45, 0.16, 0.16))
	quit.pressed.connect(_on_quit_pressed.bind(quit))


# Tall buttons so they are easy to tap on a phone; the accent colour marks the main choice.
# Keeps the fullscreen checkbox in step with F11, without sending the signal back.
func set_fullscreen_checked(on: bool) -> void:
	if _fullscreen_box:
		_fullscreen_box.set_pressed_no_signal(on)


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
