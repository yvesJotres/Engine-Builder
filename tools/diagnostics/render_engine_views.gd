extends SceneTree

# Isolated engine captures, generated from the same source model as the game.
func _init() -> void:
	var world := Node3D.new()
	root.add_child.call_deferred(world)
	await process_frame
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.08, 0.09, 0.11)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.75, 0.78, 0.82)
	environment.environment.ambient_light_energy = 0.8
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -35, 0)
	light.light_energy = 1.4
	world.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.current = true
	world.add_child(camera)
	for id in ["honda_cbr150r", "honda_cbr250rr", "ducati_panigale_v4"]:
		var spec := EngineSpec.new()
		for key in Presets.PRESETS[id]:
			spec.set(key, Presets.PRESETS[id][key])
		var model := EngineModel.new()
		world.add_child(model)
		model.build(spec)
		model.update_crank(60.0)
		var centre := model.crank_position() + Vector3(0, 1.2, -0.7)
		camera.size = maxf(8.0, model._span + 7.0)
		camera.look_at_from_position(centre + Vector3(5, 4, 7), centre)
		for assembled in [false, true]:
			model.set_assembled_view(assembled)
			for i in 10:
				await process_frame
			var path := "res://tools/diagnostics/out/engine_%s_%s.png" % [id, "assembled" if assembled else "inspection"]
			var result := root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
			print("CAPTURE %s status=%d" % [path, result])
		model.queue_free()
		await process_frame
	quit()
