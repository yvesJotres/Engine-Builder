extends SceneTree

func _init() -> void:
	await process_frame
	var published := {"honda_cbr150r": 1309.0, "honda_cbr250rr": 1390.0, "honda_cbr250rr_sp_qs": 1385.0, "honda_cbr1000rrr_sp": 1455.0, "kawasaki_zx25r": 1380.0, "kawasaki_zx25r_se": 1380.0, "yamaha_mt07": 1400.0, "yamaha_yzf_r1m": 1405.0, "ducati_panigale_v4": 1469.0, "yamaha_rd350": 1385.0}
	for id in Presets.PRESETS:
		var spec := EngineSpec.new()
		for key in Presets.PRESETS[id]:
			spec.set(key, Presets.PRESETS[id][key])
		if published.has(id):
			assert(is_equal_approx(spec.wheelbase_mm, published[id]), id + " published wheelbase")
		if spec.vehicle_type == "car":
			var car := CarModel.new()
			root.add_child(car)
			car.build(spec, 0.0)
			assert(is_equal_approx(car.front_axle.z - car.rear_axle.z, spec.wheelbase_mm * Units.MM_TO_SCENE), id + " car wheelbase")
			car.free()
			continue
		var bike := Drivetrain.new()
		root.add_child(bike)
		bike.build(0.0, Vector3(0, 2, 0), Vector3(0, 4, 0), 0.85, false, AABB(), spec)
		assert(is_equal_approx(bike.front_axle.z - bike.rear_axle.z, spec.wheelbase_mm * Units.MM_TO_SCENE), id + " wheelbase")
		var front := (bike._front_wheel.get_node("Tyre") as MeshInstance3D).mesh as TorusMesh
		var rear := (bike._wheel_pivot.get_node("Tyre") as MeshInstance3D).mesh as TorusMesh
		assert(is_equal_approx(front.inner_radius, spec.front_rim_in * 25.4 * 0.5 * Units.MM_TO_SCENE), id + " front rim")
		assert(is_equal_approx(rear.inner_radius, spec.rear_rim_in * 25.4 * 0.5 * Units.MM_TO_SCENE), id + " rear rim")
		if published.has(id):
			assert(is_equal_approx(rear.outer_radius * 0.1, EngineSim.tire_radius_m(spec)), id + " physics radius")
		assert(bike._chain_x > spec.rear_tire_width_mm * Units.MM_TO_SCENE * 0.5, id + " chain clearance")
		bike.free()
	print("vehicle dimensions: PASS (%d presets; 10 sourced motorcycle values)" % Presets.PRESETS.size())
	quit()
