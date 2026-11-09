extends SceneTree

# Graphical scene profile. Run with the normal display and audio driver.
func _init() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main._on_sound_toggled(true)
	main._touch_throttle = 0.5
	for id in ["honda_cbr150r", "honda_cbr250rr", "kawasaki_zx25r"]:
		var index: int = main._panel._preset_ids.find(id)
		if index < 0:
			push_error("Missing preset " + id)
			quit(1)
			return
		main._panel._preset_button.select(index)
		main._panel._on_preset_selected(index)
		var layout: ExhaustLayout = main._sim._audio_layout
		for routed in [false, true]:
			main._sim.set_audio_layout(layout if routed else null, main.spec.cylinders)
			var start := Time.get_ticks_usec()
			var previous := start
			var frames := 0
			var slow := 0
			var starved := 0
			var total := 0.0
			var worst := 0.0
			while Time.get_ticks_usec() - start < 3000000:
				main._sim.rpm = 6000.0
				main._sim.omega = 6000.0 * TAU / 60.0
				main._sim.running = true
				await process_frame
				var now := Time.get_ticks_usec()
				var ms := (now - previous) / 1000.0
				previous = now
				if now - start < 500000:
					continue
				frames += 1
				total += ms
				worst = maxf(worst, ms)
				if ms > 16.67:
					slow += 1
				if main._sound.starved:
					starved += 1
			print("GRAPHICS %s %s: frames %d avg %.2f ms max %.2f ms over16.67 %d starved %d" % [id, "routed" if routed else "baseline", frames, total / maxf(frames, 1), worst, slow, starved])
	main.free()
	quit()
