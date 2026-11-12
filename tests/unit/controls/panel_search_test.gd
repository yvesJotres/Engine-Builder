extends SceneTree

# Nine tabs and about a hundred rows: the search box is how a player finds "conrod ratio" without hunting. Typing hides
# every row whose label does not match and switches to the first page that has a hit; clearing the box restores each
# row's own visibility rules, because a single-cylinder engine hides Layout and a search must not leave it showing.
# Run: godot --headless --path . -s tests/unit/controls/panel_search_test.gd (prints PASS or FAIL)

var _fails := 0
var _panel


func _init() -> void:
	await process_frame
	_panel = ControlPanel.new()
	root.add_child(_panel)
	await process_frame

	check(_panel._search != null, "the panel has a search box")

	_panel._apply_search("conrod")
	check(_panel._row_labels["rod_ratio"].visible, "the conrod ratio row matches")
	check(not _panel._row_labels["bore"].visible, "a row that does not match is hidden")
	check(_panel._category == 0, "the panel switches to the page that has the hit")

	_panel._apply_search("")
	check(_panel._row_labels["bore"].visible, "clearing the search shows the row again")
	check(_panel._row_labels["rod_ratio"].visible, "and the matched row too")

	# a single-cylinder engine hides Layout; clearing the search must not reveal it
	var index: int = _panel._preset_ids.find("honda_cbr150r")
	_panel._on_preset_selected(index)
	await process_frame
	var layout_row: Label = _panel._row_labels["layout"]
	check(not layout_row.visible, "a single cylinder hides the layout row to begin with")
	_panel._apply_search("layout")
	check(layout_row.visible, "a search hit shows the row even if the engine hides it")
	_panel._apply_search("")
	check(not layout_row.visible, "clearing the search restores the engine's own visibility rule")

	_panel.queue_free()
	print("RESULT: " + ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(1 if _fails > 0 else 0)


func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1
