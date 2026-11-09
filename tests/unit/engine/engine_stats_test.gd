extends SceneTree


func _init() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main._process(1.0 / 60.0)
	var stats = main._stats
	var ok: bool = stats.get_parent() == main and not main._panel.is_ancestor_of(stats)
	ok = ok and stats._engine_data.text.contains("RPM") and stats._sensors.text.contains("Exhaust")
	var controls: Control = stats._content.get_child(0)
	ok = ok and controls.get_global_rect().end.y <= stats._engine_data.get_global_rect().position.y
	ok = ok and main._cell._readout == null
	# A shorter panel must scroll rather than place controls over the readings.
	stats._panel.anchor_bottom = 0.0
	stats._panel.offset_bottom = 360.0
	await process_frame
	await process_frame
	ok = ok and stats._scroll.get_v_scroll_bar().max_value > stats._scroll.get_v_scroll_bar().page
	ok = ok and controls.get_global_rect().end.y <= stats._engine_data.get_global_rect().position.y
	stats._toggle_stats()
	ok = ok and not stats._scroll.visible
	stats._toggle_stats()
	ok = ok and stats._scroll.visible
	main.free()
	print("RESULT: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
