extends SceneTree

# Every control must be listed on exactly one page, and on the page its own definition claims. Five were missing from
# CATEGORY_KEYS (compression, firing order, decel pops, ABS, traction control), which meant "Reset rider aids" ignored
# ABS and the search box could never find it: typing ABS matched no page, so nothing happened.
# Run: godot --headless --path . -s tests/unit/controls/panel_category_keys_test.gd (prints PASS or FAIL)

var _fails := 0


func _init() -> void:
	var missing: Array = []
	var wrong: Array = []
	var seen := {}
	for category in PanelSchema.CATEGORY_KEYS:
		for key in PanelSchema.CATEGORY_KEYS[category]:
			if seen.has(key):
				wrong.append("%s is on %s and on %s" % [key, seen[key], category])
			seen[key] = category
	for key in PanelSchema.CONTROLS:
		if not seen.has(key):
			missing.append(key)
			continue
		var want := String(PanelSchema.get_def(key).get("category", ""))
		if want != "" and String(seen[key]) != want:
			wrong.append("%s sits on %s but says %s" % [key, seen[key], want])

	check(missing.is_empty(), "every control is listed on a page: %s" % [missing])
	check(wrong.is_empty(), "and on the page it claims: %s" % [wrong])

	print("RESULT: " + ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(1 if _fails > 0 else 0)


func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1
