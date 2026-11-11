extends SceneTree

# Idle stability probe: reports rpm, intake pressure and fuel flow once a second for 15 s after start.
# Run: godot --headless --path . -s tools/diagnostics/idle_probe.gd

var _main: Node


func _init() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	await process_frame
	await process_frame
	if "--gd-clock" in OS.get_cmdline_user_args():
		_main._sim._native_clock_checked = true
		_main._sim._native_clock = null
	_main._ignition = true
	_main._touch_starter = true
	for i in 700:
		_main._process(1.0 / 60.0)
	_main._touch_starter = false
	for second in 15:
		var lo := 1e9
		var hi := 0.0
		for i in 60:
			_main._process(1.0 / 60.0)
			var rpm: float = _main._sim.rpm
			lo = minf(lo, rpm)
			hi = maxf(hi, rpm)
		print("t=%2d s  rpm %.0f..%.0f  mean %.0f  map %.1f kPa  fuel %.2f g/s  running %s" % [
			second + 1, lo, hi, (lo + hi) * 0.5, _main._sim.intake.pressure / 1000.0,
			_main._sim.fuel_flow, str(_main._sim.running)])
	quit(0)