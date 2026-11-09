extends SceneTree

func _init() -> void:
	await process_frame
	var panel := ControlPanel.new()
	root.add_child(panel)
	await process_frame
	var spec := EngineSpec.new()
	panel.apply_to(spec)
	assert(spec.intake_display == "stock")
	var original_runner := spec.runner_length_m
	panel._controls["intake_display"].select(1)
	panel._controls["stack_length"].value = 90.0
	panel.apply_to(spec)
	assert(spec.intake_display == "velocity_stack")
	assert(is_equal_approx(spec.velocity_stack_length_mm, 90.0))
	assert(is_equal_approx(spec.runner_length_m, original_runner))
	var model := EngineModel.new()
	root.add_child(model)
	model.build(spec)
	assert(not model._intake_mouths.is_empty())
	var aftermarket_mouth := model._intake_mouths[0]
	spec.intake_display = "stock"
	model.build(spec)
	assert(model._intake_mouths[0].distance_to(aftermarket_mouth) > 0.5)
	model.free()
	panel.free()
	print("intake_choice_test: PASS")
	quit(0)
