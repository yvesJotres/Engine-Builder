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
	env.environment.ambient_light_color = Color(0.85, 0.85, 0.9)
	env.environment.ambient_light_energy = 1.0
	world.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, 30, 0)
	world.add_child(light)
	var bike := Drivetrain.new()
	world.add_child(bike)
	bike.build(Ground.Y, Vector3(0, 2.0, 0), Vector3(0, 4.0, 0))
	for child in bike.get_children():
		if child.name != "Chassis":
			child.visible = false
	var chassis := bike.get_node("Chassis")
	for child in chassis.get_children():
		if not (child.name.begins_with("Swingarm") or child.name.begins_with("Axle")):
			child.visible = false
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8.0
	world.add_child(camera)
	var target := Vector3(0, 2.1, bike.rear_axle.z * 0.5)
	camera.look_at_from_position(target + Vector3(-7, 4, 6), target)
	camera.current = true
	for i in 10:
		await process_frame
	var path := ProjectSettings.globalize_path("res://tools/diagnostics/out/swingarm.png")
	var error := root.get_texture().get_image().save_png(path)
	print("Screenshot %s: %d" % [path, error])
	quit(error)
