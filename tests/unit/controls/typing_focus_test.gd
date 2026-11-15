extends SceneTree

# Typing in a text field must not ride the bike: the build-name box used to open the throttle with W, brake
# with B and shift with Q and E while the player named a build.
# Run: godot --headless --path . -s tests/unit/controls/typing_focus_test.gd (prints PASS or FAIL)

var _fails := 0


func _init() -> void:
	await process_frame
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 6:
		await process_frame
	main.set_process(false)

	check(not main._typing_in_field(), "nothing focused means the keys ride")

	var edit := LineEdit.new()
	root.add_child(edit)
	edit.grab_focus()
	await process_frame
	check(edit.has_focus(), "the text field takes the focus")
	check(main._typing_in_field(), "a focused LineEdit counts as typing")

	var text_edit := TextEdit.new()
	root.add_child(text_edit)
	text_edit.grab_focus()
	await process_frame
	check(main._typing_in_field(), "a focused TextEdit counts as typing too")

	edit.grab_focus()
	await process_frame
	main._throttle = 0.0
	# with the field focused, the throttle must not open even though W is "held"
	main._paused = false
	main._touch_throttle = 0.0
	for i in 12:
		main._process(1.0 / 60.0)
	check(main._throttle == 0.0, "the throttle stays shut while a text field has the focus")

	# once the field lets go, the keys ride again
	edit.release_focus()
	await process_frame
	check(not main._typing_in_field(), "releasing the field returns the keys to the bike")

	print("RESULT: " + ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(1 if _fails > 0 else 0)


func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1
