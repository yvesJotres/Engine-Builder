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
	env.environment.ambient_light_color = Color(0.8, 0.82, 0.86)
	env.environment.ambient_light_energy = 0.9
	world.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -30, 0)
	light.light_energy = 1.5
	world.add_child(light)
	var spec := EngineSpec.new()
	for key in Presets.PRESETS.honda_cbr250rr:
		spec.set(key, Presets.PRESETS.honda_cbr250rr[key])
	var engine := EngineModel.new()
	world.add_child(engine)
	engine.build(spec)
	engine.update_crank(60.0)
	var crank := engine.crank_position()
	var gearbox := GearboxModel.new()
	world.add_child(gearbox)
	gearbox.build(crank, spec, engine.primary_gear_x())
	var clutch := Clutch.new()
	world.add_child(clutch)
	clutch.build(crank, spec, engine.primary_gear_x())
	var exhaust := Exhaust.new()
	world.add_child(exhaust)
	exhaust.build(ExhaustLayout.build(spec, engine.exhaust_ports(), crank, Ground.Y))
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 13.0
	world.add_child(camera)
	var target := crank + Vector3(0, 0.8, -2.0)
	camera.look_at_from_position(target + Vector3(-10, 6, 9), target)
	camera.current = true
	for assembled in [false, true]:
		engine.set_assembled_view(assembled)
		for i in 10:
			await process_frame
		var path := ProjectSettings.globalize_path("res://tools/diagnostics/out/complete_engine_%s.png" % ("assembled" if assembled else "inspection"))
		print("capture %s: %d" % [path, root.get_texture().get_image().save_png(path)])
	quit()
