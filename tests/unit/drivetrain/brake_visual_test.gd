extends SceneTree

func _init() -> void:
	for fitted in [false, true]:
		var bike := Drivetrain.new()
		root.add_child(bike)
		bike.build(0.0, Vector3(0, 2, 0), Vector3(0, 4, 0), 0.85, fitted)
		var brakes := bike.get_node("BrakeHardware")
		for part in ["FrontCaliper", "RearCaliper", "FrontReservoir", "RearReservoir", "FrontBrakeHose0", "RearBrakeHose0"]:
			assert(brakes.has_node(part), "Missing " + part)
		assert(brakes.has_node("ABSModule") == fitted)
		assert(brakes.has_node("FrontABSSensor") == fitted and brakes.has_node("RearABSSensor") == fitted)
		for wheel in [bike._front_wheel, bike._wheel_pivot]:
			assert(wheel.has_node("BrakeRotor") and wheel.has_node("RotorCarrier"))
			assert(wheel.has_node("ABSToneRing") == fitted)
		bike.free()
	print("brake hardware: PASS")
	quit()
