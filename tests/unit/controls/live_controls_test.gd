extends SceneTree

# The live controls added for riding without the panel: rider-aid toggles, camera cycling, slow motion, frame stepping,
# panel/HUD hiding, mute and reset. Each is driven through the same handler the game uses, so this tests the real
# bindings rather than a copy of them.
# Run: godot --headless --path . -s tests/unit/controls/live_controls_test.gd (prints PASS or FAIL)

var _fails := 0
var _main: Node


func _init() -> void:
	await process_frame
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	for i in 6:
		await process_frame
	_main.set_process(false)
	_main._paused = false

	# --- camera cycling uses the panel's own list
	_main._camera_view = 0
	_main._cycle_camera(1)
	check(_main._camera_view == 1, "the camera key moves to the next view")
	_main._cycle_camera(0)
	check(_main._camera_view == 0, "and the other way goes back")

	# --- reset stops the bike and drops it into neutral
	_main._sim.speed = 22.0
	_main._sim.gear.gear = 3
	_key(KEY_R)
	check(_main._sim.speed == 0.0, "R stops the bike")
	check(_main._sim.gear.gear == 0, "R puts the gearbox in neutral")

	# --- slow motion is a hold, so the release must restore real time
	_tab(true)
	check(is_equal_approx(Engine.time_scale, _main.SLOW_MOTION_SCALE), "Tab slows the world right down")
	check(Engine.time_scale <= 0.1, "and it is at most a tenth of real time")
	_tab(false)
	check(is_equal_approx(Engine.time_scale, 1.0), "releasing Tab returns to real time")

	# --- panel and HUD hiding
	var panel_was: bool = _main._panel.visible
	_key(KEY_P)
	check(_main._panel.visible != panel_was, "P hides the setup panel")
	_key(KEY_P)
	check(_main._panel.visible == panel_was, "P brings it back")
	var hud_was: bool = _main._hud.visible
	_key(KEY_H)
	check(_main._hud.visible != hud_was, "H hides the HUD")
	_key(KEY_H)
	check(_main._hud.visible == hud_was, "H brings it back")

	# --- mute
	var sound_was: bool = _main._sound_on
	_key(KEY_M)
	check(_main._sound_on != sound_was, "M mutes the sound")
	_key(KEY_M)
	check(_main._sound_on == sound_was, "M unmutes it")

	# --- an aid toggle moves the panel switch AND the engine spec together
	var control = _main._panel._controls["abs_enabled"]
	var switch_was: int = control.selected
	var spec_was: bool = _main.spec.abs_enabled
	_key(KEY_Y)
	check(control.selected != switch_was, "Y flips the ABS switch in the panel")
	check(_main.spec.abs_enabled != spec_was, "and the change reaches the engine spec")
	_key(KEY_Y)
	check(_main.spec.abs_enabled == spec_was, "Y flips it back")

	# --- a frame step only does anything while paused, and pausing must stop the world
	_main._paused = true
	var frame_before: int = _main._frame
	_key(KEY_BRACKETRIGHT)
	check(_main._frame > frame_before, "] advances exactly one frame while paused")
	check(_main._paused, "and leaves the game paused")
	_main._paused = false
	frame_before = _main._frame
	_key(KEY_BRACKETRIGHT)
	check(_main._frame == frame_before, "] does nothing when the game is running")

	print("RESULT: " + ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(1 if _fails > 0 else 0)


func _key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	_main._unhandled_input(ev)


func _tab(pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_TAB
	ev.physical_keycode = KEY_TAB
	ev.pressed = pressed
	_main._unhandled_input(ev)


func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1
