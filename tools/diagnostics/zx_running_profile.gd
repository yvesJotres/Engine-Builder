extends SceneTree

func _init() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var index: int = main._panel._preset_ids.find("kawasaki_zx25r")
	main._panel._on_preset_selected(index)
	for sound_on in [true, false]:
		main._on_sound_toggled(sound_on)
		for target_rpm in [16000.0]:
			var start := Time.get_ticks_usec()
			var previous := start
			var samples: Array[float] = []
			while Time.get_ticks_usec() - start < 2500000:
				main._sim.rpm = target_rpm
				main._sim.omega = target_rpm * TAU / 60.0
				main._sim.running = true
				main._touch_throttle = 0.65
				await process_frame
				var now := Time.get_ticks_usec()
				if now - start > 500000:
					samples.append((now - previous) / 1000.0)
				previous = now
			samples.sort()
			var total := 0.0
			for sample in samples:
				total += sample
			var p95 := samples[int((samples.size() - 1) * 0.95)] if not samples.is_empty() else 0.0
			print("ZX_PROFILE sound=%s rpm=%.0f steps=%d avg=%.2f p95=%.2f frames=%d" % [sound_on, target_rpm, roundi(1.0 / main._sim.physics_dt), total / maxf(samples.size(), 1), p95, samples.size()])
	main.free()
	quit()
