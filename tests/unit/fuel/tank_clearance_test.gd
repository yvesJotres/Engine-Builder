extends SceneTree

func _init() -> void:
	await process_frame
	var count := 0
	for id in Presets.PRESETS:
		var spec := EngineSpec.new()
		for key in Presets.PRESETS[id]:
			spec.set(key, Presets.PRESETS[id][key])
		if spec.vehicle_type == "car":
			continue
		for intake_mode in ["stock", "velocity_stack"]:
			spec.intake_display = intake_mode
			var engine := EngineModel.new()
			root.add_child(engine)
			engine.build(spec)
			var tank := FuelTankModel.new()
			root.add_child(tank)
			tank.set_capacity(spec.fuel_capacity_l)
			tank.place(engine.highest_y() + 0.4, 0.0)
			var tank_low := tank.position.y - tank.size.y * 0.46 * tank.scale.y
			for mouth in engine._intake_mouths:
				var mouth_world := engine.transform * mouth
				assert(tank_low > mouth_world.y + 0.24, "%s %s: intake enters tank" % [id, intake_mode])
			tank.free()
			engine.free()
			count += 1
	print("tank/intake clearance: PASS (%d configurations)" % count)
	quit()
