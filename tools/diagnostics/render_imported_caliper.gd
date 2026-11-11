extends SceneTree

func _init() -> void:
	var world := Node3D.new()
	root.add_child.call_deferred(world)
	await process_frame
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.12, 0.13, 0.15)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.85, 0.85, 0.9)
	env.environment.ambient_light_energy = 0.8
	world.add_child(env)
	var lamp := DirectionalLight3D.new()
	lamp.rotation_degrees = Vector3(-35, 30, 0)
	world.add_child(lamp)
	var model: Node3D = load("res://assets/3d/imported/kaliper_nika23_mobile.glb").instantiate()
	world.add_child(model)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.0
	camera.look_at_from_position(Vector3(1, 4, 18), Vector3(0, 1.7, 0))
	camera.current = true
	for i in 8:
		await process_frame
	var path := ProjectSettings.globalize_path("res://tools/diagnostics/out/caliper_isolated.png")
	var err := root.get_texture().get_image().save_png(path)
	print("caliper preview: %s (%d)" % [path, err])
	quit(err)
