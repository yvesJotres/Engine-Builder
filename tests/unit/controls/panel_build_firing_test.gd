extends SceneTree

# Build save and load round trip, and the firing-order apply. Exits 1 on any failure.
# Run: godot --headless --path . -s res://tests/unit/controls/panel_build_firing_test.gd

var _fails := 0
const TEST_BUILDS := "user://panel_build_firing_test.cfg"


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func _init() -> void:
	await process_frame
	var library = EngineLibrary.get_instance()
	library._library = Presets.PRESETS
	library._ready = true
	var panel := ControlPanel.new()
	panel.builds_path = TEST_BUILDS
	root.add_child(panel)
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_BUILDS))

	_test_build_round_trip(panel)
	_test_overwrite_asks(panel)
	_test_rename_and_delete(panel)
	_test_firing_order(panel)
	_test_valve_rows(panel)
	await _test_changed_batching(panel)
	_test_twin_rows(panel)
	_test_rod_ratio_warning()

	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_BUILDS))
	print("panel_build_firing_test: %s" % ("PASSED" if _fails == 0 else "FAILED"))
	quit(1 if _fails > 0 else 0)


func _test_build_round_trip(panel: ControlPanel) -> void:
	panel._on_preset_selected(panel._preset_ids.find("kawasaki_zx25r"))
	panel._controls["intake_valve_mm"].value = 24.0
	panel._controls["runner_length_m"].value = 0.3
	panel._controls["idle"].value = 1350.0
	panel._build_name.text = "Round trip"
	panel._save_build()
	check(panel._build_status.text == "Saved: Round trip", "the build saves, got '%s'" % panel._build_status.text)

	panel._controls["intake_valve_mm"].value = 30.0
	panel._controls["runner_length_m"].value = 0.1
	panel._controls["idle"].value = 1100.0
	var sound_before: float = panel._controls["sound_rasp"].value
	panel._controls["sound_rasp"].value = sound_before + 2.0
	panel._builds.select(_find_build("Round trip", panel))
	panel._load_build()
	check(is_equal_approx(panel._controls["intake_valve_mm"].value, 24.0), "intake valve restored, got %.1f" % panel._controls["intake_valve_mm"].value)
	check(is_equal_approx(panel._controls["runner_length_m"].value, 0.3), "runner restored, got %.2f" % panel._controls["runner_length_m"].value)
	check(is_equal_approx(panel._controls["idle"].value, 1350.0), "idle restored, got %.0f" % panel._controls["idle"].value)
	check(is_equal_approx(panel._controls["sound_rasp"].value, sound_before), "sound levels are saved with the build, got %.2f" % panel._controls["sound_rasp"].value)

	var spec := EngineSpec.new()
	panel.apply_to(spec)
	check(is_equal_approx(spec.intake_valve_mm, 24.0), "the loaded intake valve reaches the spec, got %.1f" % spec.intake_valve_mm)
	check(is_equal_approx(spec.runner_length_m, 0.3), "the loaded runner reaches the spec, got %.2f" % spec.runner_length_m)


# Saving over a saved name asks first: the file keeps the old build until the user confirms.
func _test_overwrite_asks(panel: ControlPanel) -> void:
	panel._on_preset_selected(panel._preset_ids.find("kawasaki_zx25r"))
	panel._controls["idle"].value = 1000.0
	panel._build_name.text = "Round trip"
	panel._save_build()
	check(panel._overwrite_dialog != null and panel._overwrite_dialog.visible, "saving over a saved name asks first")
	var config := ConfigFile.new()
	config.load(TEST_BUILDS)
	var saved: Dictionary = config.get_value("Round trip", "controls")
	check(is_equal_approx(float(saved["idle"]), 1350.0), "the old build is kept until the user confirms, got %s" % str(saved["idle"]))
	panel._overwrite_dialog.confirmed.emit()
	config.load(TEST_BUILDS)
	saved = config.get_value("Round trip", "controls")
	check(is_equal_approx(float(saved["idle"]), 1000.0), "confirming replaces the build, got %s" % str(saved["idle"]))
	panel._overwrite_dialog.hide()


# Rename moves the selected build to the typed name; delete removes it only on confirm.
func _test_rename_and_delete(panel: ControlPanel) -> void:
	panel._builds.select(_find_build("Round trip", panel))
	panel._build_name.text = "Renamed build"
	panel._rename_build()
	var config := ConfigFile.new()
	config.load(TEST_BUILDS)
	check(config.has_section("Renamed build") and not config.has_section("Round trip"), "rename moves the build to the new name")
	check(panel._builds.get_item_text(panel._builds.selected) == "Renamed build", "the list selects the renamed build")

	panel._builds.select(_find_build("Renamed build", panel))
	panel._delete_build()
	check(panel._delete_dialog != null and panel._delete_dialog.visible, "deleting asks first")
	config.load(TEST_BUILDS)
	check(config.has_section("Renamed build"), "the build is kept until the user confirms the delete")
	panel._delete_dialog.confirmed.emit()
	config = ConfigFile.new() # a fresh read: ConfigFile.load keeps the sections of the object it is called on
	config.load(TEST_BUILDS)
	check(not config.has_section("Renamed build"), "confirming deletes the build")
	panel._delete_dialog.hide()


func _test_firing_order(panel: ControlPanel) -> void:
	# pick the first preset with four cylinders
	var found := false
	for id in panel._preset_ids:
		panel._on_preset_selected(panel._preset_ids.find(id))
		if int(panel._controls["cyl"].value) == 4:
			found = true
			break
	check(found, "a four-cylinder preset exists")
	if not found:
		return
	var before: Array = panel.fire_deg.duplicate()
	var sorted_angles: Array = before.duplicate()
	sorted_angles.sort()

	panel._firing_order.text = "1-3-4-2"
	panel._apply_firing_order()
	var after: Array = panel.fire_deg
	# cylinder 1 takes the first firing angle, 3 the second, 4 the third, 2 the fourth
	check(is_equal_approx(float(after[0]), float(sorted_angles[0])), "cylinder 1 fires first, got %s" % str(after))
	check(is_equal_approx(float(after[2]), float(sorted_angles[1])), "cylinder 3 fires second, got %s" % str(after))
	check(is_equal_approx(float(after[3]), float(sorted_angles[2])), "cylinder 4 fires third, got %s" % str(after))
	check(is_equal_approx(float(after[1]), float(sorted_angles[3])), "cylinder 2 fires fourth, got %s" % str(after))

	# a repeated cylinder is refused and leaves the angles as they were
	panel._firing_order.text = "1-1-4-2"
	panel._apply_firing_order()
	check(panel._firing_message.text == "Enter each cylinder number once.", "a repeated cylinder is refused, got '%s'" % panel._firing_message.text)
	check(panel.fire_deg == after, "a refused order changes nothing")


# Many changes in one frame reach the listeners as one changed signal.
func _test_changed_batching(panel: ControlPanel) -> void:
	var count := {"n": 0}
	var listener := func() -> void: count.n += 1
	panel.changed.connect(listener)
	for i in 5:
		panel._emit_changed()
	await process_frame
	await process_frame
	check(count.n == 1, "five changes in one frame emit changed once, got %d" % count.n)
	panel.changed.disconnect(listener)


# The crank-pin rows follow the cylinder count and the layout: a twin's pin row only for two inline cylinders.
func _test_twin_rows(panel: ControlPanel) -> void:
	panel._on_preset_selected(panel._preset_ids.find("honda_cbr150r"))
	panel._controls["cyl"].value = 2
	panel._select_text(panel._controls["layout"], "inline")
	panel._refresh_twin()
	check(panel._twin_label.visible, "a two-cylinder inline engine shows the crank pin")
	panel._select_text(panel._controls["layout"], "V")
	panel._refresh_twin()
	check(not panel._twin_label.visible, "a V engine hides the crank pin")
	check(panel._shared_pins_label.visible, "a two-cylinder V shows the crankpin pairing")
	panel._controls["cyl"].value = 1
	panel._refresh_twin()
	check(not panel._shared_pins_label.visible, "a single cylinder hides the crankpin pairing")


# A rod ratio outside 1.2 to 3.5 is named as a warning; a sensible one is not.
func _test_rod_ratio_warning() -> void:
	var spec := EngineSpec.new()
	spec.rod_ratio = 0.5
	check(spec.validation_warning() == "Rod ratio must be 1.2 to 3.5", "a rod ratio of 0.5 is refused, got '%s'" % spec.validation_warning())
	spec.rod_ratio = 1.6
	check(spec.validation_warning() != "Rod ratio must be 1.2 to 3.5", "a rod ratio of 1.6 is accepted")


# The valve and runner rows show for a four-stroke and hide for a two-stroke.
func _test_valve_rows(panel: ControlPanel) -> void:
	var seen := {"four": false, "two": false}
	for id in panel._preset_ids:
		panel._on_preset_selected(panel._preset_ids.find(id))
		var two: bool = panel._controls["stroke_type"].selected == 1
		var key := "two" if two else "four"
		seen[key] = true
		check(panel._controls["intake_valve_mm"].visible == (not two), "%s: the intake valve row is %s for a %s" % [id, "hidden" if two else "shown", key])
		check(panel._controls["runner_length_m"].visible == (not two), "%s: the runner row is %s for a %s" % [id, "hidden" if two else "shown", key])
	check(seen["four"] and seen["two"], "the presets include a four-stroke and a two-stroke to test the rows")


func _find_build(build_name: String, panel: ControlPanel) -> int:
	for i in panel._builds.item_count:
		if panel._builds.get_item_text(i) == build_name:
			return i
	return -1
