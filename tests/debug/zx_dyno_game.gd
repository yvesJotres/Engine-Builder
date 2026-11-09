extends SceneTree

# Runs the ZX-25R dyno sweep inside the full main scene, one process frame at a time, and reports wall time. Print only.
const MAX_FRAMES := 60 * 240


func _init() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 30:
		await process_frame
	var p: Dictionary = Presets.PRESETS["kawasaki_zx25r"]
	for key in p.keys():
		main.spec.set(key, p[key])
	main._on_panel_changed()
	for i in 30:
		await process_frame
	main._on_dyno_pressed()
	var worst := 0.0
	var total := 0.0
	var frames := 0
	while main._dyno.active() and frames < MAX_FRAMES:
		var t0 := Time.get_ticks_usec()
		await process_frame
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		worst = maxf(worst, ms)
		total += ms
		frames += 1
		if frames % 600 == 0:
			print("frame %d  %s  wall %.1f s  worst %.1f ms" % [frames, main._dyno.status_text(), total / 1000.0, worst])
	print("FINISHED after %d frames, %.1f s wall, worst frame %.1f ms, active %s, status: %s" % [frames, total / 1000.0, worst, str(main._dyno.active()), main._dyno.status])
	quit()
