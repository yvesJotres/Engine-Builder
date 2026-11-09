extends SceneTree

func _init() -> void:
	await process_frame
	var tank := FuelTankModel.new()
	root.add_child(tank)
	tank.set_capacity(12.0)
	var small := tank.scale.x
	tank.set_capacity(24.0)
	assert(is_equal_approx(pow(tank.scale.x / small, 3.0), 2.0))
	tank.place(5.0, 0.0)
	var outlet := tank.get_node("TankOutlet") as MeshInstance3D
	assert(tank.outlet_position().distance_to(tank.position + (outlet.position + Vector3(0, -0.07, 0)) * tank.scale) < 0.001)
	for id in ["honda_cbr250rr", "yamaha_rd350"]:
		var spec := EngineSpec.new()
		for key in Presets.PRESETS[id]:
			spec.set(key, Presets.PRESETS[id][key])
		var model := EngineModel.new()
		root.add_child(model)
		model.build(spec)
		var feeds := model.fuel_feed_positions()
		assert(feeds.size() == spec.cylinders)
		var line := FuelLine.new()
		root.add_child(line)
		line.build(tank.outlet_position(), feeds, spec.induction)
		var connectors: Array[Vector3] = []
		for child in line.get_children():
			if child.name.begins_with("FeedConnector"):
				connectors.append(child.position)
		var expected := 1 if spec.induction == "injection" else feeds.size()
		assert(connectors.size() == expected)
		for i in expected:
			assert(connectors[i].distance_to(feeds[i]) < 0.001)
		line.free()
		model.free()
	tank.free()
	print("fuel visual routing: PASS")
	quit()
