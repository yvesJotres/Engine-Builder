extends SceneTree

func _init() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var index: int = main._panel._preset_ids.find("honda_v3r900")
	if index < 0:
		push_error("Honda V3R preset missing")
		quit(1)
		return
	main._panel._on_preset_selected(index)
	main._on_sound_toggled(true)
	main._panel_starter = true
	var start := Time.get_ticks_usec()
	var previous := start
	var times: Array[float] = []
	var starved := 0
	var ran := false
	while Time.get_ticks_usec() - start < 6000000:
		var elapsed := (Time.get_ticks_usec() - start) / 1000000.0
		main._panel_starter = elapsed < 2.0
		main._touch_throttle = 0.45 if elapsed > 3.0 and elapsed < 5.0 else 0.0
		await process_frame
		var now := Time.get_ticks_usec()
		if elapsed > 1.0:
			times.append((now - previous) / 1000.0)
			if main._sound.starved:
				starved += 1
		previous = now
		ran = ran or main._sim.running
	times.sort()
	var total := 0.0
	for value in times:
		total += value
	print("V3R live: running=%s frames=%d average=%.2f ms p95=%.2f ms audio_starved=%d" % [ran, times.size(), total / maxf(times.size(), 1), times[int((times.size() - 1) * 0.95)] if not times.is_empty() else 0.0, starved])
	main.free()
	quit(0 if ran and not times.is_empty() else 1)
