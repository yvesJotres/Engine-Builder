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
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 7.0
	world.add_child(camera)
	for id in ["honda_cbr250rr", "yamaha_rd350"]:
		var spec := EngineSpec.new()
		for key in Presets.PRESETS[id]:
			spec.set(key, Presets.PRESETS[id][key])
		var engine := EngineModel.new()
		world.add_child(engine)
		engine.build(spec)
		var tank := FuelTankModel.new()
		world.add_child(tank)
		tank.set_capacity(spec.fuel_capacity_l)
		tank.update(0.75, Color(0.2, 0.4, 0.9))
		tank.place(engine.highest_y() + 0.4, (engine.crank_position().z + engine.throttle_position().z) * 0.5)
		var line := FuelLine.new()
		world.add_child(line)
		line.build(tank.outlet_position(), engine.fuel_feed_positions(), spec.induction)
		var target := (engine.crank_position() + tank.position) * 0.5
		camera.look_at_from_position(target + Vector3(8, 4, -7), target)
		camera.current = true
		for i in 10:
			await process_frame
		var path := ProjectSettings.globalize_path("res://tools/diagnostics/out/fuel_%s.png" % id)
		var error := root.get_texture().get_image().save_png(path)
		if error != OK:
			quit(error)
			return
		print("Screenshot %s" % path)
		line.free()
		tank.free()
		engine.free()
	quit()
