extends SceneTree

# Every bike can use the quickshifter and launch control. A bike without them starts with them off, and turning one on gives
# working default values: a cut profile for each gear, and the spec's own launch settings. Exits 1 on any failure.
# Run: godot --headless --path . -s res://tests/unit/controls/aids_default_test.gd

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
	var plain := panel._preset_ids.find("honda_cbr150r")
	check(plain >= 0, "the CBR150R is in the preset list")
	if plain < 0:
		print("aids_default_test: FAILED")
		quit(1)
		return
	panel._on_preset_selected(plain)
	var spec := EngineSpec.new()
	panel.apply_to(spec)
	check(not spec.has_quickshifter and not spec.has_launch_control, "the CBR150R has no factory quickshifter or launch control")
	check(not spec.quickshifter and not spec.launch_control, "the aids start off on a bike without them")

	panel._controls["qs_enabled"].select(1)
	panel._controls["launch_control"].select(1)
	panel.apply_to(spec)
	check(spec.quickshifter, "the quickshifter turns on for a bike without one")
	check(spec.launch_control, "launch control turns on for a bike without one")
	check(spec.quickshifter_cut_profile.size() == 6, "a turned-on quickshifter has a cut profile for each gear, got %d" % spec.quickshifter_cut_profile.size())
	check(spec.quickshifter_cut_time > 0.0 and spec.quickshifter_min_rpm > 0.0, "the quickshifter has a cut time and an engagement speed")
	check(spec.launch_rpm > 0.0 and spec.launch_throttle > 0.0, "launch control has its default rpm and throttle")
	check(not spec.has_quickshifter and not spec.has_launch_control, "the factory fit is not changed by switching the aids on")

	var zx := panel._preset_ids.find("kawasaki_zx25r")
	if zx >= 0:
		panel._on_preset_selected(zx)
		panel.apply_to(spec)
		check(spec.has_quickshifter and spec.quickshifter, "the ZX-25R still starts with its quickshifter on")

	print("aids_default_test: %s" % ("PASSED" if _fails == 0 else "FAILED"))
	quit(0 if _fails == 0 else 1)
