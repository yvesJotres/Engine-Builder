extends SceneTree

# A validation warning must point at the page that holds the control, and clicking it must take you there. Without this
# the panel says "Rod ratio must be 1.2 to 3.5" while the row is two tabs away and off screen.
# Run: godot --headless --path . -s tests/unit/controls/warning_tab_test.gd (prints PASS or FAIL)

var _fails := 0


func _init() -> void:
	await process_frame
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 6:
		await process_frame
	main.set_process(false)

	var engine_tab: Button = main._panel._tabs[0] # CATEGORIES[0] is "Engine"
	var valve_tab: Button = main._panel._tabs[3] # CATEGORIES[3] is "Valvetrain"

	main._panel.set_warning("Rod ratio must be 1.2 to 3.5", "rod_ratio")
	check(String(engine_tab.text).contains("*"), "the tab that owns the control is marked")
	check(not String(valve_tab.text).contains("*"), "the other tabs are not")

	main._panel.set_warning("", "")
	check(not String(engine_tab.text).contains("*"), "clearing the warning clears the mark")

	# clicking the warning jumps to the page
	main._panel._select_category(3)
	main._panel.set_warning("Rod ratio must be 1.2 to 3.5", "rod_ratio")
	main._panel.jump_to_warning()
	check(main._panel._category == 0, "the warning jumps to the Engine page")

	print("RESULT: " + ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(1 if _fails > 0 else 0)


func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1
