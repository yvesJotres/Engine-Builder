extends SceneTree

func _init() -> void:
	var world := Node3D.new()
	root.add_child.call_deferred(world)
	await process_frame
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.08, 0.09, 0.11)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.85, 0.85, 0.9)
	env.environment.ambient_light_energy = 0.8
	world.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 30, 0)
	world.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 13.0
	world.add_child(camera)
	camera.look_at_from_position(Vector3(-12, 9, -3), Vector3(0, 1, -3))
	camera.current = true
	for style in ["stock", "sport", "short"]:
		var spec := EngineSpec.new()
		for key in Presets.PRESETS.honda_cbr250rr:
			spec.set(key, Presets.PRESETS.honda_cbr250rr[key])
		spec.muffler_style = style
		var visual := Exhaust.new()
		world.add_child(visual)
		visual.build(ExhaustLayout.build(spec))
		for frame in 8:
			await process_frame
		var path := "res://tools/diagnostics/out/exhaust_%s.png" % style
		print("capture %s: %d" % [path, root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))])
		visual.queue_free()
		await process_frame
	quit()
