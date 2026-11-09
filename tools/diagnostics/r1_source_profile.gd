extends SceneTree

var _preset := "yamaha_yzf_r1m"

# Bounded, real-time source scene check with the normal render and audio drivers.
func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--preset="):
			_preset = arg.substr(9).validate_filename()
	Engine.max_fps = 60
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child.call_deferred(main)
	await process_frame
	await process_frame
	main.set_process(false)
	main._panel._on_preset_selected(main._panel._preset_ids.find(_preset))
	main._ignition = true
	main._panel_starter = true
	await _stage(main, "starting", 2.0)
	main._panel_starter = false
	var idle := await _stage(main, "idle", 3.0)
	main._touch_throttle = 1.0
	await _stage(main, "rev rise", 3.0)
	var high := await _stage(main, "high rev", 3.0)
	var file := FileAccess.open("res://build/accuracy/%s_source_profile.json" % _preset, FileAccess.WRITE)
	file.store_string(JSON.stringify({"idle": idle, "high_rev": high}, "  "))
	main.free()
	quit()


func _stage(main: Node, label: String, seconds: float) -> Dictionary:
	var start := Time.get_ticks_usec()
	var previous := start
	var frames := []
	var sim_ms := []
	var starved := 0
	while Time.get_ticks_usec() - start < seconds * 1e6:
		await process_frame
		var now := Time.get_ticks_usec()
		frames.append((now - previous) / 1000.0)
		previous = now
		var dt := root.get_process_delta_time()
		var before := Time.get_ticks_usec()
		main._process(dt)
		sim_ms.append((Time.get_ticks_usec() - before) / 1000.0)
		if main._sound.starved:
			starved += 1
	frames.sort()
	sim_ms.sort()
	var result := {"frames": frames.size(), "fps": frames.size() * 1e6 / (Time.get_ticks_usec() - start), "frame_p95_ms": frames[int(frames.size() * 0.95)], "game_update_p95_ms": sim_ms[int(sim_ms.size() * 0.95)], "audio_starved_frames": starved, "rpm": main._sim.rpm, "running": main._sim.running}
	print("%s source %s: %s" % [_preset, label, JSON.stringify(result)])
	return result
