extends SceneTree

# The panel needs to know WHICH control a validation warning is about, so it can mark the tab and jump to the row.
# The text itself must not change: other tests assert the exact strings.
# Run: godot --headless --path . -s tests/unit/controls/validation_problem_test.gd (prints PASS or FAIL)

var _fails := 0


func _init() -> void:
	await process_frame
	var spec := EngineSpec.new()
	var problem := spec.validation_problem()
	check(String(problem.get("text", "")) == "", "a fresh spec has no problem")
	check(String(problem.get("key", "")) == "", "and no offending control")

	# a rod ratio out of range: the text is the one the panel has always shown, and the key is the row that fixes it
	spec.rod_ratio = 0.5
	problem = spec.validation_problem()
	check(String(problem.get("text", "")) == "Rod ratio must be 1.2 to 3.5",
		"the warning text is unchanged, got '%s'" % String(problem.get("text", "")))
	check(String(problem.get("key", "")) == "rod_ratio", "and it names the conrod ratio row")
	check(spec.validation_warning() == String(problem.get("text", "")),
		"validation_warning() still returns the same text for the old callers")

	# every key a warning can name must be a real panel row, or the badge and the jump would point at nothing
	spec.rod_ratio = 1.6
	spec.cylinders = 3
	spec.layout = "V"
	spec.ignition_offset_deg = 30.0
	check(_key_resolves(spec), "the key names a control the panel actually builds")
	check(spec.validation_warning() != "", "and there is still a warning")

	print("RESULT: " + ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(1 if _fails > 0 else 0)


func _key_resolves(spec: EngineSpec) -> bool:
	var key := String(spec.validation_problem().get("key", ""))
	if key == "":
		return false
	return not PanelSchema.get_def(key).is_empty()


func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1
