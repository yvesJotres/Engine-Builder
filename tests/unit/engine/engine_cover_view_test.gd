extends SceneTree

func _init() -> void:
	var model := EngineModel.new()
	root.add_child(model)
	for preset_id in ["honda_cbr150r", "honda_cbr250rr", "ducati_panigale_v4"]:
		var spec := EngineSpec.new()
		for key in Presets.PRESETS[preset_id]:
			spec.set(key, Presets.PRESETS[preset_id][key])
		model.set_assembled_view(false)
		model.build(spec)
		assert(model._covers.size() == 1 + 3 * spec.cylinders)
		for cover in model._covers:
			assert(not cover.visible)
		model.set_assembled_view(true)
		for cover in model._covers:
			assert(cover.visible)
		for shell in model._inspection_shells:
			assert(not shell.visible)
		for angle in range(0, 720, 15):
			model.update_crank(float(angle))
			for piston in model._pistons:
				assert(piston.position.is_finite())
		model.build(spec)
		assert(model._covers[0].visible)
		await process_frame
	model.free()
	print("engine_cover_view_test: PASS")
	quit(0)
