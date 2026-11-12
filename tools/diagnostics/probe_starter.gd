extends SceneTree

# Probe: hold J and watch what the game does with it frame by frame.

func _init() -> void:
	await process_frame
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 6:
		await process_frame
	main.set_process(false)
	main._paused = false
	main._ignition = true
	main._sim.gear.gear = 0
	print("start: rpm=%.1f ignition=%s gear=%d paused=%s" % [main._sim.rpm, main._ignition, main._sim.gear.gear, main._paused])

	var ev := InputEventKey.new()
	ev.keycode = KEY_J
	ev.physical_keycode = KEY_J
	ev.pressed = true
	Input.parse_input_event(ev)
	print("starter reads: ", KeyboardControls.starter(false))

	for i in 60:
		main._process(1.0 / 60.0)
		if i % 10 == 0:
			print("frame %2d  rpm=%6.1f  throttle=%.2f  clutch_engage=%.2f" % [
				i, main._sim.rpm, main._throttle, main._sim.clutch_engage])
	print("end: rpm=%.1f" % main._sim.rpm)
	quit(0)
