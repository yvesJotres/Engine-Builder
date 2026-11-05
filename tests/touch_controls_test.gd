# Run: godot --headless --path . -s tests/touch_controls_test.gd (prints PASS or FAIL)
extends SceneTree

# Pushes touch events into the running main scene: the throttle and clutch levers pulled at once, a spring-back on
# release, a shift tap, STARTER and PAUSE.
var _main: Node
var _touch: CanvasLayer
var _step := 0
var _wait := 0
var _fails := 0


func _process(_delta: float) -> bool:
	_wait += 1
	if _step == 0:
		if _wait == 1:
			_main = load("res://scenes/main.tscn").instantiate()
			root.add_child(_main)
		if _wait < 6:
			return false
		for child in _main.get_children():
			if child is TouchControls:
				_touch = child
		_touch.visible = true
		_step = 1
		_wait = 0
		return false
	if _wait < 3:
		return false # let the containers lay out before reading the controls
	match _step:
		1:
			_wait = 0
			_touch_at("THROTTLE", 0, true)
			_touch_at("CLUTCH", 1, true)
			_check("throttle and clutch levers both pulled", _main._touch_throttle > 0.0 and _main._touch_clutch > 0.0)
			_step = 2
		2:
			# the levers spring back over about a quarter of a second, so give them time before checking
			if _wait < 40:
				return false
			_wait = 0
			_touch_at("THROTTLE", 0, false)
			_step = 3
		3:
			if _wait < 40:
				return false
			_wait = 0
			_check("throttle springs back to closed on release", _main._touch_throttle == 0.0)
			_check("clutch lever still pulled while held", _main._touch_clutch > 0.0)
			_touch_at("CLUTCH", 1, false)
			_step = 4
		4:
			if _wait < 40:
				return false
			_wait = 0
			_check("clutch lever springs back to engaged on release", _main._touch_clutch == 0.0)
			_step = 5
		5:
			var gear_before: int = _main._sim.gear.gear
			_touch_at("SHIFT +", 2, true)
			_touch_at("SHIFT +", 2, false)
			_check("shift + tap changes gear (%d -> %d)" % [gear_before, _main._sim.gear.gear], _main._sim.gear.gear != gear_before)
			_touch_at("STARTER", 4, true)
			_check("STARTER hold sets the starter", _main._touch_starter)
			_touch_at("STARTER", 4, false)
			_check("STARTER released", not _main._touch_starter)
			_touch_at("PAUSE", 3, true)
			_check("PAUSE tap pauses", _main._paused)
			_touch_at("PAUSE", 3, false)
			print("RESULT: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
			quit(1 if _fails > 0 else 0)
	return false


# Finds a pad or a lever by the label on it.
func _control(label: String) -> Control:
	for node in _touch.find_children("*", "", true, false):
		if (node is TouchControls.Pad or node is TouchControls.Lever) and node.get_child(0).text == label:
			return node
	push_error("no control " + label)
	return null


# Touches the centre of a control. A lever read at its centre is pulled halfway.
func _touch_at(label: String, index: int, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.pressed = pressed
	ev.position = _control(label).get_global_rect().get_center()
	root.push_input(ev)


func _check(what: String, ok: bool) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1
