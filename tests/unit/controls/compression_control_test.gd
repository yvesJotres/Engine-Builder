extends SceneTree

# The compression ratio is a control on the Engine page now, and every bike keeps its own number. Three things have to
# hold: the control shows the preset's ratio for that bike, turning it changes the spec AND the engine the sim builds,
# and a saved build brings the tweaked value back.
# Run: godot --headless --path . -s res://tests/unit/controls/compression_control_test.gd   (prints PASS or FAIL)

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func _init() -> void:
	var panel := ControlPanel.new()
	panel.builds_path = "user://compression_test.cfg"
	root.add_child(panel)
	await process_frame

	var spin: SpinBox = panel._controls["cr"]
	print("control: %.1f..%.1f step %.1f, unit '%s'" % [spin.min_value, spin.max_value, spin.step, PanelSchema.get_def("cr").unit])
	check(spin.min_value == 6.0 and spin.max_value == 15.0, "the control is a ratio, clamped 6:1 to 15:1")
	check(PanelSchema.get_def("cr").spec_field == "compression_ratio", "it drives the spec's compression_ratio")

	# ---- each bike carries its own value ----
	var bikes := ["kawasaki_zx25r_se", "harley_sportster_883", "ducati_panigale_v4"]
	for id in bikes:
		var index := panel._preset_ids.find(id)
		if index < 0:
			check(false, "preset %s is in the panel" % id)
			continue
		panel._on_preset_selected(index)
		var spec := EngineSpec.new()
		panel.apply_to(spec)
		print("%s: control %.1f, spec %.1f" % [id, spin.value, spec.compression_ratio])
		check(absf(spin.value - spec.compression_ratio) < 1.0e-6, "%s's control and its spec agree (%.1f)" % [id, spin.value])
		var from_data: float = float(Presets.PRESETS[id].get("compression_ratio", 0.0))
		check(absf(spec.compression_ratio - from_data) < 1.0e-6,
			"%s carries its own ratio (%.1f, the preset says %.1f)" % [id, spec.compression_ratio, from_data])

	# ---- turning it changes the engine the sim builds ----
	var index := panel._preset_ids.find("kawasaki_zx25r_se")
	panel._on_preset_selected(index)
	var spec := EngineSpec.new()
	panel.apply_to(spec)
	var before := spec.compression_ratio
	spin.value = 13.0
	panel.apply_to(spec)
	print("turned to 13.0: spec %.1f, panel var %.1f" % [spec.compression_ratio, panel.compression_ratio])
	check(absf(spec.compression_ratio - 13.0) < 1.0e-6, "the control writes the spec (%.1f)" % spec.compression_ratio)
	check(absf(panel.compression_ratio - 13.0) < 1.0e-6, "the plain var mirrors it for saving (%.1f)" % panel.compression_ratio)
	check(spec.compression_ratio > before, "raised from the bike's own %.1f" % before)
	var sim := EngineSim.new()
	sim.fuel.set_kind(spec.fuel)
	sim.step(1.0 / 60.0, spec, 0.0, false, false, false, false, 1.0) # builds the cylinders from this spec
	print("engine built from it: geometric ratio %.2f:1" % sim.compression_ratio_geometric())
	check(absf(sim.compression_ratio_geometric() - 13.0) < 1.0e-6,
		"the simulated engine really compresses 13:1 (%.3f)" % sim.compression_ratio_geometric())

	# ---- a saved build brings the tweaked value back ----
	panel._build_name.text = "Compression test"
	panel._save_build()
	spin.value = 9.0
	panel._load_build()
	panel.apply_to(spec)
	print("after saving 13.0 and loading: %.1f" % spec.compression_ratio)
	check(absf(spec.compression_ratio - 13.0) < 1.0e-6, "a saved build keeps the tweaked ratio (%.1f)" % spec.compression_ratio)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(panel.builds_path))
	panel.free()
	if _fails == 0:
		print("compression_control_test: PASS (on the panel, per bike, and it builds what it says)")
	quit(0 if _fails == 0 else 1)
