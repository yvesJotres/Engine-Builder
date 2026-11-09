extends SceneTree


func _init() -> void:
	var panel := ControlPanel.new()
	panel.builds_path = "user://shared_crankpin_test.cfg"
	root.add_child(panel)
	await process_frame
	var index := panel._preset_ids.find("honda_v3r900")
	panel._on_preset_selected(index)
	panel._controls["shared_pins"].select(1)
	panel._controls["shared_pins"].item_selected.emit(1)
	var spec := EngineSpec.new()
	panel.apply_to(spec)
	var angles := FiringOrders.for_spec(spec)
	var ok := spec.shared_v_crankpins and angles.size() == 3
	ok = ok and absf(fposmod(angles[1] - angles[0] - spec.bank_angle, 360.0)) < 0.001
	var model := EngineModel.new()
	root.add_child(model)
	model.build(spec)
	var sim := EngineSim.new()
	sim._build_cylinders(spec)
	ok = ok and is_equal_approx(sim.cylinders[1].phi, fposmod(-angles[1], 720.0))
	for crank in [0.0, 70.0, 190.0, 340.0]:
		model.update_crank(crank)
		var ends := []
		for i in [0, 1]:
			var wrist: Vector3 = model.to_local(model._pistons[i].global_position)
			var middle: Vector3 = model.to_local(model._rods[i].global_position)
			ends.append(2.0 * middle - wrist)
		ok = ok and absf(ends[0].y - ends[1].y) < 0.001 and absf(ends[0].z - ends[1].z) < 0.001
		ok = ok and absf(ends[0].x - ends[1].x) > 0.01
	ok = ok and absf(model._pin_x[2] - (model._pin_x[0] + model._pin_x[1]) / 2.0) > 0.1
	model.free()
	panel._build_name.text = "Shared V3"
	panel._save_build()
	panel._controls["shared_pins"].select(0)
	panel._load_build()
	panel.apply_to(spec)
	ok = ok and spec.shared_v_crankpins
	panel._controls["bank_angle"].value = 60.0
	panel.apply_to(spec)
	var adjusted := FiringOrders.for_spec(spec)
	sim._build_cylinders(spec)
	ok = ok and absf(fposmod(adjusted[1] - adjusted[0] - 60.0, 360.0)) < 0.001
	ok = ok and is_equal_approx(sim.cylinders[1].phi, fposmod(-adjusted[1], 720.0))
	panel._controls["shared_pins"].select(0)
	panel.apply_to(spec)
	ok = ok and not spec.shared_v_crankpins and FiringOrders.for_spec(spec) == Array(spec.fire_deg, TYPE_FLOAT, "", null)
	var v4 := EngineSpec.new()
	v4.cylinders = 4
	v4.layout = "V"
	v4.bank_angle = 90.0
	v4.shared_v_crankpins = true
	v4.fire_deg = [0.0, 270.0, 360.0, 630.0]
	var v4_model := EngineModel.new()
	root.add_child(v4_model)
	v4_model.build(v4)
	var station_one := (v4_model._pin_x[0] + v4_model._pin_x[1]) * 0.5
	var station_two := (v4_model._pin_x[2] + v4_model._pin_x[3]) * 0.5
	ok = ok and absf(station_one - station_two) > 0.1
	v4_model.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(panel.builds_path))
	panel.free()
	print("RESULT: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
