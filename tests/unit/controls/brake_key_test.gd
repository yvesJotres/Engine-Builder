extends SceneTree

# Brake is Space and only Space: B was removed from the brake on request, so it must do nothing at all.
# Run: godot --headless --path . -s tests/unit/controls/brake_key_test.gd (prints PASS or FAIL)

var _fails := 0


func _init() -> void:
	await process_frame

	check(not KeyboardControls.brake(false), "nothing held means not braking")

	_key(KEY_B, true)
	await process_frame
	check(not KeyboardControls.brake(false), "B does nothing")

	_key(KEY_B, false)
	_key(KEY_SPACE, true)
	await process_frame
	check(KeyboardControls.brake(false), "Space brakes")
	check(not KeyboardControls.brake(true), "Space does not brake while a text field has the focus")

	_key(KEY_SPACE, false)
	await process_frame
	check(not KeyboardControls.brake(false), "releasing Space stops braking")

	print("RESULT: " + ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(1 if _fails > 0 else 0)


func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)


func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1
