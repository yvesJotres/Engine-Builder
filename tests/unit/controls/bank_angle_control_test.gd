extends SceneTree


func _init() -> void:
	var panel := ControlPanel.new()
	panel.builds_path = "user://bank_angle_test.cfg"
	root.add_child(panel)
	await process_frame
	var index := panel._preset_ids.find("honda_v3r900")
	panel._on_preset_selected(index)
	var ok: bool = panel._controls["bank_angle"].visible and panel._controls["bank_angle"].value == 75.0
	panel._controls["bank_angle"].value = 60.0
	var spec := EngineSpec.new()
	panel.apply_to(spec)
	ok = ok and spec.bank_angle == 60.0 and panel.bank_angle == 60.0
	panel._build_name.text = "Angle test"
	panel._save_build()
	panel._controls["bank_angle"].value = 90.0
	panel._load_build()
	panel.apply_to(spec)
	ok = ok and spec.bank_angle == 60.0
	var config := ConfigFile.new()
	config.load(panel.builds_path)
	var controls: Dictionary = config.get_value("Angle test", "controls")
	controls.erase("bank_angle")
	config.set_value("Angle test", "controls", controls)
	config.set_value("Angle test", "bank_angle", 75.0)
	config.save(panel.builds_path)
	panel._load_build()
	panel.apply_to(spec)
	ok = ok and spec.bank_angle == 75.0
	panel._select_text(panel._controls["layout"], "inline")
	panel._refresh_twin()
	ok = ok and not panel._controls["bank_angle"].visible
	DirAccess.remove_absolute(ProjectSettings.globalize_path(panel.builds_path))
	panel.free()
	print("RESULT: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
