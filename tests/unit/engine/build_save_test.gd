extends SceneTree


func _init() -> void:
	var panel := ControlPanel.new()
	panel.builds_path = "user://build_save_test.cfg"
	root.add_child(panel)
	await process_frame
	panel._build_name.text = "Test build"
	panel._controls["bore"].value = 65.0
	panel._controls["boost_ratio"].value = 1.37
	panel._controls["compressor_battery"].value = 55.0
	panel.compression_ratio = 12.3
	panel._vehicle_settings = {"vehicle_type": "car", "wheelbase_mm": 2500.0, "runner_bore_mm": 41.0}
	panel._save_build()
	panel._controls["bore"].value = 50.0
	panel._controls["boost_ratio"].value = 1.0
	panel._controls["compressor_battery"].value = 10.0
	panel.compression_ratio = 9.0
	panel._vehicle_settings = {}
	panel._load_build()
	var spec := EngineSpec.new()
	panel.apply_to(spec)
	var ok := is_equal_approx(spec.bore_mm, 65.0) and is_equal_approx(spec.compression_ratio, 12.3)
	ok = ok and is_equal_approx(spec.max_boost_ratio, 1.37) and is_equal_approx(spec.compressor_battery_wh, 55.0)
	ok = ok and spec.vehicle_type == "car" and is_equal_approx(spec.wheelbase_mm, 2500.0)
	ok = ok and is_equal_approx(spec.runner_bore_mm, 41.0)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(panel.builds_path))
	panel.free()
	print("PASS build save and load" if ok else "FAIL build save and load")
	quit(0 if ok else 1)
