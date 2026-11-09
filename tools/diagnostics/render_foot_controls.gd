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
	env.environment.ambient_light_energy = 1.0
	world.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, 30, 0)
	world.add_child(light)
	var bike := Drivetrain.new()
	world.add_child(bike)
	bike.build(Ground.Y, Vector3(0, 2.0, 0), Vector3(0, 4.0, 0))
	for child in bike.get_children():
		child.visible = child.name == "FootControls"
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.6
	world.add_child(camera)
	var target := Vector3(0, 1.8, -0.7)
	for side in [1, -1]:
		camera.look_at_from_position(target + Vector3(side * 5, 2.5, 4), target)
		camera.current = true
		for i in 10:
			await process_frame
		var filename := "shift" if side == 1 else "brake"
		var path := ProjectSettings.globalize_path("res://tools/diagnostics/out/foot_controls_%s.png" % filename)
		var error := root.get_texture().get_image().save_png(path)
		if error != OK:
			quit(error)
			return
		print("Screenshot %s" % path)
	quit()
