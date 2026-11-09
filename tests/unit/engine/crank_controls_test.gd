extends SceneTree


func _init() -> void:
	var panel := ControlPanel.new()
	panel.builds_path = "user://crank_controls_test.cfg"
	root.add_child(panel)
	await process_frame
	var spec := EngineSpec.new()
	panel._controls["slant"].value = -35.0
	panel._controls["cyl"].value = 2
	panel._controls["twin"].select(3)
	panel._controls["custom_pin"].value = 234.0
	panel._on_twin_selected(3)
	panel.apply_to(spec)
	var ok := spec.slant_deg == -35.0 and spec.twin_pin_deg == 234.0 and spec.fire_deg == [0.0, 234.0]
	var sim := EngineSim.new()
	sim._build_cylinders(spec)
	ok = ok and is_equal_approx(sim.cylinders[1].phi, 486.0)
	var model := EngineModel.new()
	root.add_child(model)
	model.build(spec)
	ok = ok and is_equal_approx(model.rotation_degrees.x, -35.0)
	ok = ok and is_equal_approx(model._pin_phase[1], -234.0)
	model.free()
	panel._controls["cyl"].value = 3
	panel._controls["crank"].select(2)
	panel._on_crank_selected(2)
	panel.apply_to(spec)
	ok = ok and spec.fire_deg == [0.0, 180.0, 450.0]
	panel._controls["cyl"].value = 4
	panel._controls["crank"].select(2)
	panel._on_crank_selected(2)
	panel._firing_order.text = "1-2-3-4"
	panel._apply_firing_order()
	panel.apply_to(spec)
	ok = ok and spec.crossplane and spec.fire_deg == [0.0, 270.0, 450.0, 540.0]
	var before := spec.fire_deg.duplicate()
	panel._firing_order.text = "1-2-2-4"
	panel._apply_firing_order()
	ok = ok and panel.fire_deg == before
	panel._build_name.text = "Crank test"
	panel._save_build()
	panel._controls["slant"].value = 0
	panel._controls["cyl"].value = 2
	panel._load_build()
	panel.apply_to(spec)
	ok = ok and spec.slant_deg == -35.0 and spec.cylinders == 4 and spec.fire_deg == before
	DirAccess.remove_absolute(ProjectSettings.globalize_path(panel.builds_path))
	panel.free()
	print("RESULT: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
