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
	env.environment.ambient_light_color = Color(0.8, 0.82, 0.85)
	env.environment.ambient_light_energy = 1.0
	world.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 30, 0)
	world.add_child(light)
	var spec := EngineSpec.new()
	var model := GearboxModel.new()
	world.add_child(model)
	model.build(Vector3.ZERO, spec, -0.6)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.0
	world.add_child(camera)
	camera.look_at_from_position(Vector3(-3, 3, 2), Vector3(0, 0, -0.7))
	camera.current = true
	for i in 10:
		await process_frame
	var path := ProjectSettings.globalize_path("res://tools/diagnostics/out/gearbox.png")
	var error := root.get_texture().get_image().save_png(path)
	print("Screenshot %s: %d" % [path, error])
	quit(error)
