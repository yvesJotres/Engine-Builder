extends SceneTree

# Presses the dyno test button in the real main scene: the test starts by itself, shifting is blocked while it runs, the
# view opens and shows the rpm, Stop ends the test, and Close hides the view. Also checks the kill switch stops a start.
# Run: godot --headless -s tests/integration/dyno/dyno_view_test.gd (exit code 1 on failure)

var _fails := 0
var _main: Node


func check(ok: bool, msg: String) -> void:
	print(("ok   " if ok else "FAIL ") + msg)
	if not ok:
		_fails += 1


func _run(frames: int) -> void:
	for i in frames:
		_main._process(1.0 / 60.0)


func _init() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	await process_frame
	await process_frame

	_main._ignition = false
	_main._panel.dyno_pressed.emit()
	check(not _main._dyno.active(), "with the kill switch on, the dyno test does not start")

	_main._ignition = true
	_main._pending_shift = 1
	_main._panel.dyno_pressed.emit()
	check(_main._dyno.active(), "the dyno button starts the test")
	check(_main._dyno_view.is_open(), "the dyno view opens")
	check(_main._dyno_view._panel.offset_bottom <= -250.0, "the dyno panel stops above the dashboard")
	check(_main._dyno_view._panel.anchor_top == 0.0, "the dyno panel hangs from the top of the screen")
	check(_main._pending_shift == 0, "starting the dyno cancels pending manual shifts")

	_main._shift(true)
	check(_main._sim.gear.gear == 0, "shifting is blocked while the test runs")

	_run(600) # ten seconds: the engine starts and the first gear is under way
	var text: String = _main._dyno_view._status.text
	print("view status after 10 s: " + text)
	check(_main._dyno.active(), "the test is still running after 10 s")
	check(text.find("rpm") != -1, "the view shows the rpm while it runs")
	check(is_equal_approx(_main._hud._panel.rpm, _main._sim.rpm), "dashboard displays the current engine rpm")
	check(is_equal_approx(_main._hud._panel.speed, _main._sim.speed * 3.6), "dashboard displays the current speed")
	check(_main._hud._panel.gear == _main._sim.gear.label(), "dashboard displays the current gear")
	_main._hud.flash("TEST ALERT")
	check(_main._hud._panel.flash_text == "TEST ALERT" and _main._hud._panel.flash_time > 0.0, "dashboard displays alerts")

	_main._dyno_view._on_button() # the button reads Stop while running
	check(not _main._dyno.active(), "Stop ends the test")
	check(_main._dyno_view.is_open(), "the view stays open after Stop, showing what was read")
	check(not _main._dyno.ok, "a stopped test is marked as not finished")

	_main._dyno_view._on_button() # now it reads Close
	check(not _main._dyno_view.is_open(), "Close hides the view")

	_main._panel.dyno_pressed.emit()
	check(_main._dyno.active() and _main._dyno_view.is_open(), "the button starts a second test, after a stop")
	_main._panel.dyno_pressed.emit()
	check(not _main._dyno.active(), "pressing the button again while it runs stops it")

	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
