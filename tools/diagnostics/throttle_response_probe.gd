extends SceneTree

# What the player actually perceives when W is pressed: the throttle plate value, the rpm and the exhaust flow, sampled
# every 100 ms of simulated time at 60 fps. The plate reaching 1.0 is not the same as the engine answering, and this
# separates the two so "it takes over a second" can be attributed to the right stage.
# Run: godot --headless --path . -s res://tools/diagnostics/throttle_response_probe.gd

const DT := 1.0 / 60.0


func _init() -> void:
	await process_frame
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 6:
		await process_frame

	# start the engine the way the panel does, so the run is not measuring a dead engine
	main._touch_starter = true
	for i in 30:
		main._process(DT)
	main._touch_starter = false
	for i in 60:
		main._process(DT)
	print("idle before the press: %.0f rpm, throttle %.2f, running %s"
		% [main._sim.rpm, main._throttle, str(main._sim.running)])

	var press := InputEventKey.new()
	press.physical_keycode = KEY_W
	press.keycode = KEY_W
	press.pressed = true
	Input.parse_input_event(press)
	await process_frame
	main._throttle = 0.0
	main._throttle_last = 0.0
	main._hud.mode = 1 # the Throttle % readout only exists in HUD mode 1

	print("\n t(s)   throttle    rpm   HUD text (what the panel shows)")
	var t := 0.0
	var next_report := 0.0
	var plate_full := -1.0
	var rpm_peak := 0.0
	var rpm_settled := -1.0
	for i in 300:                       # 5 s at 60 fps
		main._process(DT)
		t += DT
		rpm_peak = maxf(rpm_peak, main._sim.rpm)
		if plate_full < 0.0 and main._throttle >= 1.0:
			plate_full = t
		if t >= next_report:
			print("%5.2f    %6.3f   %5.0f   %s" % [t, main._throttle, main._sim.rpm, main._hud._panel.info])
			next_report += 0.1

	# how long until rpm stops rising by more than 1% over 100 ms
	var prev := 0.0
	for i in 100:
		main._process(DT)
		t += DT

	var release := InputEventKey.new()
	release.physical_keycode = KEY_W
	release.keycode = KEY_W
	release.pressed = false
	Input.parse_input_event(release)

	print("\nplate fully open at %.3f s" % plate_full)
	print("rpm at 1.0 s: see the table; peak over 5 s %.0f rpm" % rpm_peak)
	print("THROTTLE_SPEED = %.2f/s -> %.3f s analytic" % [main.THROTTLE_SPEED, 1.0 / main.THROTTLE_SPEED])
	quit(0)
