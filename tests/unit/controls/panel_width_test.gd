extends SceneTree

# The panel is a fixed-width column beside the 3D view. It used to widen and narrow as you changed tab or preset, because
# the widest thing on any page set the width: a long preset name in the dropdown, a long row label. The width must be
# the same on every page, and no page may ask for more than PANEL_WIDTH.
# Run: godot --headless --path . -s tests/unit/controls/panel_width_test.gd (prints PASS or FAIL)

var _fails := 0
var _panel


func _init() -> void:
	await process_frame
	_panel = ControlPanel.new()
	root.add_child(_panel)
	await process_frame

	# the longest preset name is the widest thing the preset dropdown ever has to show
	var longest := ""
	for id in _panel._preset_ids:
		if String(id).length() > longest.length():
			longest = String(id)
	var index: int = _panel._preset_ids.find(longest)
	if index >= 0:
		_panel._on_preset_selected(index)
	await process_frame

	var frame: Control = _panel.get_child(0)
	var first := 0.0
	for i in ControlPanel.CATEGORIES.size():
		_panel._select_category(i)
		await process_frame
		var w: float = frame.get_combined_minimum_size().x
		if i == 0:
			first = w
		else:
			check(absf(w - first) < 0.5, "category %d keeps the panel width (%.1f vs %.1f)" % [i, w, first])
	check(first <= ControlPanel.PANEL_WIDTH + 0.5,
		"no page asks for more than the set width (%.1f <= %.1f)" % [first, ControlPanel.PANEL_WIDTH])

	_panel.queue_free()
	print("RESULT: " + ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(1 if _fails > 0 else 0)


func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1
