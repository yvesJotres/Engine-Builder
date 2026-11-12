extends SceneTree

# The app opens with the engine from the previous session, the one the dropdown shows. It used to remember only the
# name: the dropdown showed last session's bike while the engine inside stayed at the spec defaults, so a rider who
# closed on a Harley reopened on a 150 cc single wearing the Harley's label.
# Run: godot --headless --path . -s tests/unit/controls/last_engine_restore_test.gd (prints PASS or FAIL)

const CFG := "user://last_engine.cfg"
const BIKE := "kawasaki_zx25r"

var _fails := 0


func _init() -> void:
	await process_frame
	var had_cfg := FileAccess.file_exists(CFG)
	var saved := FileAccess.get_file_as_string(CFG) if had_cfg else ""

	# leave the app as if it had been closed on this bike
	var cfg := ConfigFile.new()
	cfg.set_value("engine", "last_preset", BIKE)
	check(cfg.save(CFG) == OK, "the last engine can be remembered")

	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 4:
		await process_frame

	var want: Dictionary = Presets.PRESETS[BIKE]
	check(main.spec.cylinders == int(want["cylinders"]), "the engine that runs is the remembered one (cylinders %d, want %d)" % [main.spec.cylinders, int(want["cylinders"])])
	check(absf(main.spec.bore_mm - float(want["bore_mm"])) < 0.001, "the remembered engine's bore is in the spec (%.1f mm)" % main.spec.bore_mm)
	check(absf(main.spec.stroke_mm - float(want["stroke_mm"])) < 0.001, "the remembered engine's stroke is in the spec (%.1f mm)" % main.spec.stroke_mm)
	# the name on screen and the engine inside must be the same machine
	var shown_id := ""
	var index: int = main._panel._preset_button.selected
	if index >= 0 and index < main._panel._preset_ids.size():
		shown_id = str(main._panel._preset_ids[index])
	check(shown_id == BIKE, "the dropdown shows the engine that runs (%s)" % shown_id)

	main.free()
	# put this machine's own choice back, so the test leaves no trace
	if had_cfg:
		var out := FileAccess.open(CFG, FileAccess.WRITE)
		if out != null:
			out.store_string(saved)
			out.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))

	print("RESULT: " + ("PASS" if _fails == 0 else "FAIL"))
	quit(1 if _fails > 0 else 0)


func check(ok: bool, message: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + message)
