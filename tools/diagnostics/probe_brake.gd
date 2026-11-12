extends SceneTree

# Probe: hold B and watch the brake flag and the road speed frame by frame.

func _init() -> void:
	await process_frame
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 6:
		await process_frame
	main.set_process(false)
	main._paused = false
	main._ignition = true
	main._sim.gear.gear = 1
	main._sim.speed = 15.0
	print("typing_in_field=%s  focus=%s" % [main._typing_in_field(), str(root.gui_get_focus_owner())])
	print("start: speed=%.2f brake_held=%s" % [main._sim.speed, str(main._brake_held)])

	var ev := InputEventKey.new()
	ev.keycode = KEY_B
	ev.physical_keycode = KEY_B
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	print("KeyboardControls.brake reads: ", KeyboardControls.brake(false))

	for i in 60:
		main._process(1.0 / 60.0)
		if i % 10 == 0:
			print("frame %2d  speed=%6.2f  brake_held=%s  sim.brake=%.2f" % [
				i, main._sim.speed, str(main._brake_held), main._sim.brake])
	print("end: speed=%.2f" % main._sim.speed)
	quit(0)
