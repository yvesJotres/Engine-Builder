extends SceneTree


func _init() -> void:
	await process_frame
	var data: Dictionary = Presets.PRESETS.get("honda_v3r900", {})
	if data.is_empty():
		print("FAIL missing Honda V3R preset")
		quit(1)
		return
	var spec := EngineSpec.new()
	for property in spec.get_property_list():
		if data.has(property.name):
			spec.set(property.name, data[property.name])
	var ok := spec.cylinders == 3 and spec.layout == "V" and spec.bank_angle == 75.0
	ok = ok and absf(spec.calc_displacement_cc() - 900.0) < 2.0 and spec.electric_compressor
	ok = ok and spec.validation_warning().is_empty()
	var panel := ControlPanel.new()
	root.add_child(panel)
	await process_frame
	var index := panel._preset_ids.find("honda_v3r900")
	if index < 0:
		ok = false
	else:
		panel._on_preset_selected(index)
		var from_panel := EngineSpec.new()
		panel.apply_to(from_panel)
		ok = ok and from_panel.electric_compressor and is_equal_approx(from_panel.max_boost_ratio, 1.25)
		ok = ok and from_panel.bank_angle == 75.0 and from_panel.fire_deg == spec.fire_deg
	panel.free()
	var model := EngineModel.new()
	root.add_child(model)
	model.build(spec)
	model.update_crank(90.0)
	ok = ok and model.exhaust_ports().size() == 3
	# Each cylinder contributes a plug and intake high point; cylinders 1 and 3 face forward.
	ok = ok and model._high_points[0].z > 0.0 and model._high_points[2].z < 0.0 and model._high_points[4].z > 0.0
	var sim := EngineSim.new()
	sim.fuel.set_kind(spec.fuel)
	for i in 120:
		sim.step(1.0 / 60.0, spec, 0.0, true, true, false, false, 1.0)
	ok = ok and sim.cylinders.size() == 3 and sim.running and is_finite(sim.rpm)
	for i in 120:
		sim.step(1.0 / 60.0, spec, 1.0, true, false, true, false, 1.0)
	ok = ok and sim.intake.boost_ratio > 1.1 and is_finite(sim.rpm)
	model.free()
	print("RESULT: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
