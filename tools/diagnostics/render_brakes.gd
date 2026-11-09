extends SceneTree

func _init() -> void:
	var world := Node3D.new()
	root.add_child.call_deferred(world)
	await process_frame
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.09, 0.10, 0.12)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.85, 0.87, 0.9)
	env.environment.ambient_light_energy = 0.9
	world.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 30, 0)
	world.add_child(light)
	var bike := Drivetrain.new()
	world.add_child(bike)
	var fitted := not OS.get_cmdline_user_args().has("--no-abs")
	bike.build(0.0, Vector3(0, 2, 0), Vector3(0, 4, 0), 0.85, fitted)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.5
	world.add_child(camera)
	var target := bike.front_axle
	camera.look_at_from_position(target + Vector3(-18, 2, 1), target)
	camera.current = true
	for i in 10:
		await process_frame
	var path := ProjectSettings.globalize_path("res://tools/diagnostics/out/brake_disc_%s.png" % ("abs" if fitted else "non_abs"))
	var error := root.get_texture().get_image().save_png(path)
	print("Screenshot %s: %d" % [path, error])
	quit(error)
