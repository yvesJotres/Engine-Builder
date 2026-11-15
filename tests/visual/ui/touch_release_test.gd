extends SceneTree

# A finger that slides off an on-screen control before it is lifted sends its release somewhere else. The Pad and the
# Lever must still let go: a brake or a throttle left held with no finger on it is the worst failure in the app.
# Run: godot --headless --path . -s tests/visual/ui/touch_release_test.gd (prints PASS or FAIL)

var _fails := 0


func _init() -> void:
	await process_frame
	var pad := TouchControls.Pad.new("BRAKE", Vector2(120, 90), Color(0.9, 0.25, 0.2))
	var lever := TouchControls.Lever.new("THROTTLE", Vector2(120, 220), Color(0.25, 0.75, 0.35))
	root.add_child(pad)
	root.add_child(lever)
	for i in 3:
		await process_frame

	var pad_events: Array = []
	pad.held.connect(func(on: bool) -> void: pad_events.append(on))

	# press both with one finger
	# one finger on the pad, another on the lever, as two hands would
	var pad_down := InputEventScreenTouch.new()
	pad_down.index = 0
	pad_down.pressed = true
	pad_down.position = pad.get_global_rect().get_center()
	pad._gui_input(pad_down)
	var lever_down := InputEventScreenTouch.new()
	lever_down.index = 1
	lever_down.pressed = true
	lever_down.position = Vector2(lever.size.x * 0.5, 4)
	lever._gui_input(lever_down)
	check(pad._down, "the pad is held while the finger is on it")
	check(lever._dragging and lever.amount > 0.0, "the lever is pulled while the finger is on it")

	# both are lifted in the corner of the screen, nowhere near either control
	for index in [0, 1]:
		var up := InputEventScreenTouch.new()
		up.index = index
		up.pressed = false
		up.position = Vector2(2, 2)
		root.push_input(up)
	for i in 40:
		await process_frame

	check(not pad._down, "a release anywhere lets the pad go")
	check(pad_events == [true, false], "the pad reports one press and one release")
	check(not lever._dragging, "a release anywhere ends the lever drag")
	check(lever.amount == 0.0, "the lever springs back to rest after a release somewhere else")

	# a second finger picks up the lever normally afterwards
	var second := InputEventScreenTouch.new()
	second.index = 2
	second.pressed = true
	second.position = Vector2(lever.size.x * 0.5, 4)
	lever._gui_input(second)
	check(lever.amount > 0.8, "the lever still works after a lost release")
	var second_up := InputEventScreenTouch.new()
	second_up.index = 2
	second_up.pressed = false
	second_up.position = Vector2(2, 2)
	root.push_input(second_up)
	for i in 40:
		await process_frame
	check(lever.amount == 0.0, "and it lets go of the second finger too")

	print("RESULT: " + ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(1 if _fails > 0 else 0)


func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1
