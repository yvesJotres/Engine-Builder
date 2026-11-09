extends SceneTree


func _init() -> void:
	var view := DynoView.new()
	view.reference_path = "user://dyno_reference_test.json"
	root.add_child(view)
	await process_frame
	view._latest_curve = [{"rpm": 4000.0, "torque": 12.5, "hp": 9.6}]
	view._reference_button.disabled = false
	view._save_reference()
	var reference := view._load_reference()
	var ok := reference.size() == 1 and is_equal_approx(float(reference[0].torque), 12.5)
	view._reference_id = "honda_cbr250rr"
	view._save_reference()
	ok = ok and view._load_reference().size() == 1
	view._reference_id = "honda_cbr150r"
	ok = ok and view._load_reference().is_empty()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(view.reference_path))
	view.free()
	print("PASS dyno reference save and load" if ok else "FAIL dyno reference")
	quit(0 if ok else 1)
