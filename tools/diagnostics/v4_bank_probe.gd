extends SceneTree

# Diagnostic: prints where each piston sits at its top dead centre, against the crank centre. Print only.
func _init() -> void:
	await process_frame
	var spec := EngineSpec.new()
	var preset: Dictionary = Presets.PRESETS["Ducati Panigale V4 (1,103 cc)"]
	for key in preset:
		spec.set(key, preset[key])
	var model := EngineModel.new()
	root.add_child(model)
	model.build(spec)
	var fire := FiringOrders.for_spec(spec)
	print("crank_y %.4f  rod_len %.4f  stroke %.4f" % [model._crank_y, model._rod_len, model._stroke])
	for i in 4:
		model.update_crank(fire[i])
		var piston: Node3D = model._pistons[i]
		var local_in_model := model.to_local(piston.global_position)
		var parent_basis := (piston.get_parent() as Node3D).transform.basis
		print("cyl %d fire %.0f  piston local %s  model-local %s  parent basis x %s y %s z %s  pos %s" % [
			i + 1, fire[i], str(piston.position), str(local_in_model),
			str(parent_basis.x.round()), str(parent_basis.y.round()), str(parent_basis.z.round()),
			str(piston.get_parent().position)])
	quit(0)
