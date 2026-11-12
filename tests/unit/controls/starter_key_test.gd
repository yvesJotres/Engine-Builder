extends SceneTree

# J is the cranking button: held to turn the starter, the same as the on-screen HOLD TO START. It must be a hold, not a
# toggle, and it must not fire while a text field owns the focus (naming a build is not riding).
# Run: godot --headless --path . -s tests/unit/controls/starter_key_test.gd (prints PASS or FAIL)

var _fails := 0


func _init() -> void:
	await process_frame

	check(not KeyboardControls.starter(false), "no key held means no cranking")

	_key(KEY_J, true)
	await process_frame
	check(KeyboardControls.starter(false), "J cranks the starter")
	check(not KeyboardControls.starter(true), "J does not crank while typing in a text field")

	_key(KEY_J, false)
	await process_frame
	check(not KeyboardControls.starter(false), "releasing J stops the starter")

	# and the key must actually reach the sim: held J should wind the engine over
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 6:
		await process_frame
	main.set_process(false)
	main._paused = false
	main._ignition = true
	main._sim.gear.gear = 0
	var before: float = main._sim.rpm
	_key(KEY_J, true)
	await process_frame # the physical key state lands on the next input pass, not at the call
	for i in 30:
		main._process(1.0 / 60.0)
	_key(KEY_J, false)
	check(main._sim.rpm > before + 10.0,
		"holding J winds the engine over (%.0f -> %.0f rpm)" % [before, main._sim.rpm])

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
