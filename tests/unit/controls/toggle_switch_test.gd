extends SceneTree

# The on/off switch behaves like the dropdown it replaces: select() sets the state silently, a tap flips it and emits
# item_selected, and an unpressed or non-mouse event does nothing. Exits 1 on any failure.
# Run: godot --headless --path . -s res://tests/unit/controls/toggle_switch_test.gd

var _fails := 0
var _emitted: Array = []


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func _init() -> void:
	await process_frame
	var toggle := ToggleSwitch.new()
	toggle.add_item("Off")
	toggle.add_item("On")
	root.add_child(toggle)
	check(toggle.item_count == 2, "two items, got %d" % toggle.item_count)
	check(toggle.get_item_text(0) == "Off" and toggle.get_item_text(1) == "On", "the item texts are Off and On")
	check(toggle.selected == 0, "starts Off")

	toggle.item_selected.connect(func(index: int) -> void: _emitted.append(index))
	toggle.select(1)
	check(toggle.selected == 1, "select(1) turns it on")
	check(_emitted.is_empty(), "select() is silent, like the dropdown")

	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	toggle._gui_input(press)
	check(toggle.selected == 0, "a tap turns it off")
	check(_emitted == [0], "a tap emits item_selected with the new state, got %s" % str(_emitted))

	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	toggle._gui_input(release)
	check(toggle.selected == 0 and _emitted.size() == 1, "releasing the button does nothing")

	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	toggle._gui_input(right)
	check(toggle.selected == 0 and _emitted.size() == 1, "a right-click does nothing")

	toggle.select(5)
	check(toggle.selected == 1, "an out-of-range select clamps to the last item")

	print("toggle_switch_test: %s" % ("PASSED" if _fails == 0 else "FAILED"))
	quit(0 if _fails == 0 else 1)
