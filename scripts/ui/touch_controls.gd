class_name TouchControls
extends CanvasLayer

# On-screen controls for phones. BRAKE, the shift buttons, STARTER and PAUSE are pads: hold or tap. CLUTCH and THROTTLE
# are levers: drag up to pull them. A lever reports how far it is pulled (0 to 1) and springs back to rest when released:
# the throttle to closed, the clutch to engaged. Each control takes its own finger, so several can be used at once.
# The mouse works the same way, which is how this is tested on a PC.
signal throttle_changed(amount: float) # 0 = closed, 1 = wide open
signal clutch_changed(amount: float) # 0 = engaged, 1 = pulled in
signal brake_changed(held: bool)
signal starter_changed(held: bool)
signal shift_pressed(up: bool)
signal pause_pressed

const SPRING_TIME := 0.25 # s, a released lever springs back to rest in about this time


func _ready() -> void:
	visible = OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()
	# On the 1920x1080 layout: the margins clear the control panel on the left and the dashboard in the bottom right.
	# The bottom margin leaves a gap above the dashboard so the pads do not run into it.
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE # the empty parts of the screen still orbit the camera
	margin.add_theme_constant_override("margin_left", 340)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 290)
	add_child(margin)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(top)
	top.add_child(_spacer())
	top.add_child(_pad("PAUSE", Vector2(130, 70), Color(0.45, 0.47, 0.55), func(on: bool) -> void: if on: pause_pressed.emit()))
	column.add_child(_spacer(true))

	var bottom := HBoxContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_theme_constant_override("separation", 10)
	column.add_child(bottom)
	bottom.add_child(_lever("CLUTCH", Vector2(150, 260), Color(0.25, 0.55, 0.95), func(v: float) -> void: clutch_changed.emit(v)))
	bottom.add_child(_pad("BRAKE", Vector2(170, 130), Color(0.9, 0.25, 0.2), func(on: bool) -> void: brake_changed.emit(on)))
	bottom.add_child(_pad("SHIFT -", Vector2(150, 130), Color(0.95, 0.7, 0.2), func(on: bool) -> void: if on: shift_pressed.emit(false)))
	bottom.add_child(_pad("SHIFT +", Vector2(150, 130), Color(0.95, 0.7, 0.2), func(on: bool) -> void: if on: shift_pressed.emit(true)))
	bottom.add_child(_pad("STARTER", Vector2(150, 130), Color(0.3, 0.8, 0.8), func(on: bool) -> void: starter_changed.emit(on)))
	bottom.add_child(_spacer())
	bottom.add_child(_lever("THROTTLE", Vector2(180, 260), Color(0.25, 0.75, 0.35), func(v: float) -> void: throttle_changed.emit(v)))


func _spacer(vertical := false) -> Control:
	var gap := Control.new()
	if vertical:
		gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gap


func _pad(text: String, min_size: Vector2, accent: Color, handler: Callable) -> Pad:
	var pad := Pad.new(text, min_size, accent)
	pad.size_flags_vertical = Control.SIZE_SHRINK_END # stay on the bottom edge when a lever is taller
	pad.held.connect(handler)
	return pad


func _lever(text: String, min_size: Vector2, accent: Color, handler: Callable) -> Lever:
	var lever := Lever.new(text, min_size, accent)
	lever.size_flags_vertical = Control.SIZE_SHRINK_END
	lever.changed.connect(handler)
	return lever


# A pad that reports each press and release. It looks like a raised button that lights up in its accent colour
# while a finger or the mouse is on it. Touch and the mouse copy of a touch arrive together, so only a change counts.
class Pad extends Panel:
	signal held(on: bool)
	var _down := false
	var _idle: StyleBoxFlat
	var _lit: StyleBoxFlat

	func _init(text: String, min_size: Vector2, accent: Color) -> void:
		custom_minimum_size = min_size
		_idle = _style(Color(0.12, 0.13, 0.16, 0.8), Color(0.45, 0.47, 0.53, 0.9))
		_lit = _style(accent, Color(1.0, 1.0, 1.0, 0.9))
		add_theme_stylebox_override("panel", _idle)
		add_child(TouchControls._label(text))

	func _style(fill: Color, border: Color) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = fill
		s.border_color = border
		s.set_border_width_all(3)
		s.set_corner_radius_all(14)
		return s

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventScreenTouch:
			_set_down(event.pressed)
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			_set_down(event.pressed)
		else:
			return
		accept_event()

	func _set_down(down: bool) -> void:
		if down != _down:
			_down = down
			# the lit style is the visible sign that the control is held
			add_theme_stylebox_override("panel", _lit if down else _idle)
			held.emit(down)


# A vertical lever. Drag it up to pull it; the lower the finger, the less it is pulled. It shows how far it is pulled
# as a filled column, and springs back to rest when released.
class Lever extends Panel:
	signal changed(amount: float)
	var amount := 0.0 # 0 = at rest, 1 = fully pulled up
	var _dragging := false
	var _accent: Color

	func _init(text: String, min_size: Vector2, accent: Color) -> void:
		custom_minimum_size = min_size
		_accent = accent
		var s := StyleBoxFlat.new()
		s.bg_color = Color(0.12, 0.13, 0.16, 0.8)
		s.border_color = Color(0.45, 0.47, 0.53, 0.9)
		s.set_border_width_all(3)
		s.set_corner_radius_all(14)
		s.set_expand_margin_all(0)
		add_theme_stylebox_override("panel", s)
		var label := TouchControls._label(text)
		label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		label.offset_bottom = -10
		add_child(label)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventScreenTouch or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
			_dragging = event.pressed
			if _dragging:
				_set_from(event.position.y)
			accept_event()
		elif _dragging and (event is InputEventScreenDrag or event is InputEventMouseMotion):
			_set_from(event.position.y)
			accept_event()

	func _set_from(y: float) -> void:
		_set_amount(clampf(1.0 - y / size.y, 0.0, 1.0))

	func _set_amount(value: float) -> void:
		if not is_equal_approx(value, amount):
			amount = value
			changed.emit(amount)
			queue_redraw()

	func _process(delta: float) -> void:
		# spring back to rest when let go
		if not _dragging and amount > 0.0:
			_set_amount(move_toward(amount, 0.0, delta / TouchControls.SPRING_TIME))

	func _draw() -> void:
		var fill := size.y * amount
		draw_rect(Rect2(0, size.y - fill, size.x, fill), _accent)


static func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color(0.96, 0.96, 0.98))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
