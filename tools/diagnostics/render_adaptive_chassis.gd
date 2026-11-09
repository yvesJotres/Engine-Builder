extends SceneTree

func _init() -> void:
	var world := Node3D.new()
	root.add_child.call_deferred(world)
	await process_frame
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.09, 0.1, 0.12)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.85, 0.87, 0.9)
	env.environment.ambient_light_energy = 0.9
	world.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 30, 0)
	world.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 17.0
	world.add_child(camera)
	for id in ["honda_cbr150r", "kawasaki_zx25r", "ducati_panigale_v4"]:
		var spec := EngineSpec.new()
		for key in Presets.PRESETS[id]:
			spec.set(key, Presets.PRESETS[id][key])
		var engine := EngineModel.new()
		world.add_child(engine)
		engine.build(spec)
		var tank := FuelTankModel.new()
		world.add_child(tank)
		tank.place(engine.highest_y() + 0.4, (engine.crank_position().z + engine.throttle_position().z) * 0.5)
		var bike := Drivetrain.new()
		world.add_child(bike)
		var bounds := engine.chassis_envelope()
		var width := maxf(0.85, maxf(absf(bounds.position.x), absf(bounds.end.x)) + 0.25)
		bike.build(Ground.Y, GearboxModel.countershaft_position(engine.crank_position(), spec), tank.outlet_position(), width, spec.has_abs, bounds, spec)
		var target := Vector3(0, 3, (bike.rear_axle.z + bike.front_axle.z) * 0.5)
		camera.look_at_from_position(target + Vector3(-18, 7, 5), target)
		camera.current = true
		for i in 10:
			await process_frame
		var path := ProjectSettings.globalize_path("res://tools/diagnostics/out/chassis_%s.png" % id)
		var error := root.get_texture().get_image().save_png(path)
		if error != OK:
			quit(error)
			return
		print("Screenshot %s" % path)
		bike.free()
		engine.free()
		tank.free()
	quit()
