extends SceneTree

# Drives the real main scene, the way the game runs it: ignition on, the starter, an idle, then the throttle open. The engine's
# settings come from the control panel here, not from the spec defaults, so a panel that clamps or mis-sets a value shows up.
# Run: godot --headless -s tests/game_idle_test.gd (exit code 1 on failure)

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
	_main._ignition = true
	_main._touch_starter = true
	_run(700) # crank until it fires
	_main._touch_starter = false
	_run(900) # settle at idle
	var idle: float = _main._sim.rpm
	print("idle in the real scene: %.0f rpm, flow %.2f g/s, intake %.1f kPa" % [idle, _main._sim.fuel_flow, _main._sim.intake.pressure / 1000.0])
	check(_main._sim.running, "the engine runs")
	check(idle > 900.0 and idle < 1700.0, "idle is near the 1,200 rpm target (%.0f rpm)" % idle)
	_main._touch_throttle = 1.0
	_run(120)
	var wot: float = _main._sim.rpm
	print("two seconds at full throttle in the real scene: %.0f rpm" % wot)
	check(wot > idle + 3000.0, "full throttle raises the rpm well above idle (%.0f rpm)" % wot)
	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
