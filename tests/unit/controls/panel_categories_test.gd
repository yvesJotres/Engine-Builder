extends SceneTree

# The reworked panel: seven category pages and their tabs, Forced induction and Rider aids shown only for bikes that have them,
# ABS and traction control hidden until they are built, a reset that puts back only its own category, and the shift force and flat
# shift settings reaching the spec and the ECU. Exits 1 on any failure.
# Run: godot --headless --path . -s res://tests/unit/controls/panel_categories_test.gd

var _fails := 0


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
	root.add_child(panel)
	await process_frame

	check(panel._tabs.size() == 7, "seven category tabs, got %d" % panel._tabs.size())
	check(panel._pages_root.get_child_count() == 7, "seven pages, got %d" % panel._pages_root.get_child_count())
	check(panel._pages_root.get_child(1).name == "Intake and fuel" and panel._pages_root.get_child(4).name == "Forced induction", "pages follow the tab order")

	# a plain bike sees neither optional category; a quickshifter bike sees Rider aids; a compressor bike sees Forced induction
	_pick(panel, "honda_cbr150r")
	check(not panel._tabs[4].visible, "the CBR150R has no Forced induction tab")
	check(not panel._tabs[5].visible, "the CBR150R has no Rider aids tab")
	_pick(panel, "kawasaki_zx25r")
	check(panel._tabs[5].visible, "the ZX-25R has a Rider aids tab")
	check(not panel._tabs[4].visible, "the ZX-25R has no Forced induction tab")
	_pick(panel, "honda_v3r900")
	check(panel._tabs[4].visible, "the V3R has a Forced induction tab")

	# a hidden category is left for the first page
	panel._select_category(5)
	_pick(panel, "honda_cbr150r")
	check(panel._category == 0, "leaving for a bike without Rider aids returns to the Engine page, got %d" % panel._category)

	# ABS and traction control stay hidden, whatever the preset fits
	for name in Presets.PRESETS:
		_pick(panel, name)
		check(not panel._controls["abs_enabled"].visible, "%s: ABS stays hidden until it is built" % name)
		check(not panel._controls["traction_control_enabled"].visible, "%s: traction control stays hidden until it is built" % name)

	# a reset puts back only its own category
	_pick(panel, "kawasaki_zx25r")
	var preset: Dictionary = Presets.PRESETS["kawasaki_zx25r"]
	var idle_before: float = panel._controls["idle"].value
	panel._controls["idle"].value = idle_before + 300.0
	panel._controls["redline"].value = float(preset["redline_rpm"]) + 1500.0
	panel._reset_category(6) # Vehicle
	check(is_equal_approx(panel._controls["redline"].value, float(preset["redline_rpm"])), "the Vehicle reset restores the redline, got %.0f" % panel._controls["redline"].value)
	check(is_equal_approx(panel._controls["idle"].value, idle_before + 300.0), "the Vehicle reset leaves the Ignition idle alone, got %.0f" % panel._controls["idle"].value)
	panel._reset_category(3) # Ignition
	check(is_equal_approx(panel._controls["idle"].value, idle_before), "the Ignition reset restores the idle, got %.0f" % panel._controls["idle"].value)

	# shift force and flat shift reach the spec
	_pick(panel, "kawasaki_zx25r")
	panel._controls["qs_sensitivity"].value = 0.4
	panel._controls["qs_flat_shift"].select(1)
	var spec := EngineSpec.new()
	panel.apply_to(spec)
	check(is_equal_approx(spec.quickshifter_sensitivity, 0.4), "the shift force reaches the spec, got %.2f" % spec.quickshifter_sensitivity)
	check(spec.quickshifter_flat_shift, "flat shift reaches the spec")

	# and flat shift holds the throttle through the cut; with it off the throttle closes
	spec.quickshifter = true
	var held := ECU.new()
	held.trigger_quickshifter(spec)
	var with_flat := held.update(0.001, 6000.0, 1.0, true, spec)
	check(is_equal_approx(with_flat, spec.flat_shift_throttle), "flat shift holds the throttle through the cut, got %.2f" % with_flat)
	spec.quickshifter_flat_shift = false
	var closed := ECU.new()
	closed.trigger_quickshifter(spec)
	var without := closed.update(0.001, 6000.0, 1.0, true, spec)
	check(is_equal_approx(without, 0.0), "with flat shift off the throttle closes through the cut, got %.2f" % without)

	print("panel_categories_test: %s" % ("PASSED" if _fails == 0 else "FAILED"))
	quit(1 if _fails > 0 else 0)


func _pick(panel: ControlPanel, id: String) -> void:
	panel._on_preset_selected(panel._preset_ids.find(id))
