extends SceneTree

# Dragging a slider fires the panel's changed signal many times per second, and every one of those used to rebuild the
# whole 3D bike. A burst of changes must collapse into ONE rebuild, and the geometry must be rebuildable on demand for
# anything that needs it immediately (startup, preset load, tests).
# Run: godot --headless --path . -s tests/unit/controls/rebuild_debounce_test.gd (prints PASS or FAIL)

var _fails := 0


func _init() -> void:
	await process_frame
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 6:
		await process_frame
	main.set_process(false)

	check(main.rebuilds_done >= 1, "startup built the bike once (%d)" % main.rebuilds_done)

	var before: int = main.rebuilds_done
	for i in 5:
		main._panel.changed.emit()
	check(main.rebuilds_done == before, "a burst of changes does not rebuild on the spot")

	main.flush_rebuild()
	check(main.rebuilds_done == before + 1, "flush_rebuild() collapses the burst into one rebuild")
	main.flush_rebuild()
	check(main.rebuilds_done == before + 1, "flushing again with nothing pending does nothing")

	# the spec side of a change must still be immediate: gear ratios feed the gearbox, not the geometry
	main._sim.gear.gear_ratios = []
	main._panel.changed.emit()
	check(main._sim.gear.gear_ratios.size() > 0, "the cheap half of a change still applies at once")

	print("RESULT: " + ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(1 if _fails > 0 else 0)


func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1
