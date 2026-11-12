extends SceneTree

# How long the throttle takes to open from closed to wide open while W is held, driven through the real _process with a
# real key event, not by re-implementing THROTTLE_SPEED. Prints the time at 60 and 120 fps so the frame quantisation is
# visible. Compare with the measured return: 0.075 s to slam shut (THROTTLE_RETURN_SPEED = 13.3).
# Run: godot --headless --path . -s res://tools/diagnostics/throttle_open_probe.gd

func _init() -> void:
	await process_frame
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 4:
		await process_frame

	var press := InputEventKey.new()
	press.physical_keycode = KEY_W
	press.keycode = KEY_W
	press.pressed = true
	Input.parse_input_event(press)
	await process_frame

	print("W reads as held: ", Input.is_physical_key_pressed(KEY_W))
	print("THROTTLE_SPEED = %.2f full travel/s -> %.3f s analytically" % [main.THROTTLE_SPEED, 1.0 / main.THROTTLE_SPEED])

	for fps in [60.0, 120.0, 144.0]:
		var dt: float = 1.0 / float(fps)
		main._throttle = 0.0
		main._paused = false
		var t := 0.0
		var frames := 0
		while main._throttle < 1.0 and t < 5.0:
			main._process(dt)
			t += dt
			frames += 1
		print("%5.0f fps: %.4f s  (%d frames, %.3f s of it quantisation)" % [fps, t, frames, t - 1.0 / main.THROTTLE_SPEED])

	# per-frame opening, so the ramp shape is not just the endpoint
	main._throttle = 0.0
	print("\nopening at 60 fps, first 8 frames:")
	var dt60 := 1.0 / 60.0
	for i in 8:
		main._process(dt60)
		print("  frame %d  throttle %.3f" % [i + 1, main._throttle])

	var release := InputEventKey.new()
	release.physical_keycode = KEY_W
	release.keycode = KEY_W
	release.pressed = false
	Input.parse_input_event(release)
	quit(0)
