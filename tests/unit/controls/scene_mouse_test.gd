extends SceneTree

# The mouse over a panel belongs to the panel. The wheel over a spin box used to change the setting AND zoom the bike,
# so scrolling the settings page pulled the camera in with it. Over the 3D view the camera must still work.
# Run: godot --headless --path . -s tests/unit/controls/scene_mouse_test.gd (prints PASS or FAIL)

var _fails := 0
var _main
var _orbit


func _init() -> void:
	await process_frame
	root.size = Vector2i(1600, 900)
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	for i in 4:
		await process_frame
	_orbit = _main._orbit
	var frame: Control = _main._panel.get_child(0)
	var over_panel: Vector2 = frame.get_global_rect().get_center()
	var over_scene := Vector2(1000, 300)

	# 1. wheel over the panel: the setting owns it, the camera does not move
	_move(over_panel)
	await process_frame
	var distance_before: float = _orbit.distance
	_wheel(over_panel, MOUSE_BUTTON_WHEEL_UP)
	await process_frame
	check(is_equal_approx(_orbit.distance, distance_before), "the wheel over the panel does not zoom the camera (%.3f -> %.3f)" % [distance_before, _orbit.distance])

	# 2. wheel over the 3D view still zooms
	_move(over_scene)
	await process_frame
	distance_before = _orbit.distance
	_wheel(over_scene, MOUSE_BUTTON_WHEEL_UP)
	await process_frame
	check(_orbit.distance < distance_before - 0.01, "the wheel over the 3D view still zooms (%.3f -> %.3f)" % [distance_before, _orbit.distance])

	# 3. a left drag over the panel does not orbit
	_move(over_panel)
	await process_frame
	var yaw_before: float = _orbit.yaw
	_drag(over_panel, 40.0)
	await process_frame
	check(is_equal_approx(_orbit.yaw, yaw_before), "a drag over the panel does not orbit the camera")

	# 4. a left drag over the 3D view still orbits
	_move(over_scene)
	await process_frame
	yaw_before = _orbit.yaw
	_drag(over_scene, 40.0)
	await process_frame
	check(not is_equal_approx(_orbit.yaw, yaw_before), "a drag over the 3D view still orbits the camera")

	_main.free()
	print("RESULT: " + ("PASS" if _fails == 0 else "FAIL"))
	quit(1 if _fails > 0 else 0)


func _move(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	root.push_input(motion)


func _wheel(at: Vector2, button: int) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = button
		ev.pressed = pressed
		ev.position = at
		ev.global_position = at
		root.push_input(ev)


func _drag(at: Vector2, dx: float) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = at
	press.global_position = at
	root.push_input(press)
	var motion := InputEventMouseMotion.new()
	motion.position = at + Vector2(dx, 0)
	motion.global_position = at + Vector2(dx, 0)
	motion.relative = Vector2(dx, 0)
	root.push_input(motion)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = at + Vector2(dx, 0)
	release.global_position = at + Vector2(dx, 0)
	root.push_input(release)


func check(ok: bool, message: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + message)
