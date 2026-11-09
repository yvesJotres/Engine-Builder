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
	env.environment.ambient_light_color = Color(0.85, 0.87, 0.9)
	env.environment.ambient_light_energy = 0.9
	world.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -35, 0)
	world.add_child(light)
	var clutch := Clutch.new()
	world.add_child(clutch)
	clutch.build(Vector3.ZERO, EngineSpec.new(), 0.0)
	clutch.update(30.0, 0.5)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.8
	world.add_child(camera)
	camera.look_at_from_position(clutch.position + Vector3(2.5, 1.4, 2.5), clutch.position)
	camera.current = true
	for i in 10:
		await process_frame
	var path := ProjectSettings.globalize_path("res://tools/diagnostics/out/clutch.png")
	var result := root.get_texture().get_image().save_png(path)
	print("capture %s: %d" % [path, result])
	quit(result)
