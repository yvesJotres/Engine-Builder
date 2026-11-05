extends SceneTree

# Runs the real main scene through the game's own frame function with a fixed time step, so a slow machine does not
# change the result. Each run: crank with the starter until 900 rpm, idle for 3 s, rev at full throttle for 3 s, then a
# 10 s coast-down in neutral. Prints the rpm each second. Run both 60 fps and 20 fps to see the effect of the frame rate.
# Run: godot --headless -s tools/diagnostics/game_coast_check.gd

var _main: Node


func _init() -> void:
	await process_frame # autoloads are registered after _init
	for fps in [60.0, 20.0]:
		await _run(1.0 / fps, fps)
	quit()


func _run(dt: float, fps: float) -> void:
	if _main != null:
		_main.free()
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	await process_frame # let the scene build its panel first, or its startup signals reset the ignition below
	_main.set_process(false) # the test calls the game's frame function itself, with the fixed time
	print("--- %d fps (frame time %.4f s)" % [int(fps), dt])

	_main._ignition = true
	_main._starter_held = true
	var t := 0.0
	var trace := ""
	while _main._sim.rpm < 900.0 and t < 60.0:
		_main._process(dt)
		t += dt
		if int(round(t / dt)) % 60 == 0:
			trace += " %.0f" % _main._sim.rpm
	print("rpm each second while cranking:" + trace)
	print("starter released at %.1f s, rpm %.0f" % [t, _main._sim.rpm])
	_main._starter_held = false

	var line := ""
	for s in 3:
		_frames(dt, 1.0)
		line += " %.0f" % _main._sim.rpm
	print("idle, rpm each second:" + line)

	_main._touch_throttle = 1.0
	line = ""
	for s in 3:
		_frames(dt, 1.0)
		line += " %.0f" % _main._sim.rpm
	print("full throttle, rpm each second:" + line)

	_main._touch_throttle = 0.0
	line = ""
	for s in 10:
		_frames(dt, 1.0)
		line += " %.0f" % _main._sim.rpm
	print("coast-down, rpm each second:" + line)


func _frames(dt: float, seconds: float) -> void:
	var n := int(round(seconds / dt))
	for i in n:
		_main._process(dt)
