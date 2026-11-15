extends SceneTree

# The brake hardware is fixed to the chassis, never to a wheel: two radial calipers straddling the twin front discs, one at
# the back on its bracket and torque arm, master cylinders with reservoirs, and lines that follow the fork leg.
# Run: godot --headless --path . -s tests/unit/drivetrain/brake_visual_test.gd

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func _init() -> void:
	await process_frame
	for fitted in [false, true]:
		var bike := Drivetrain.new()
		root.add_child(bike)
		bike.build(0.0, Vector3(0.0, 2.0, 0.0), Vector3(0.0, 4.0, 0.0), 0.85, fitted)
		var brakes := bike.get_node("BrakeHardware")
		var label := "ABS" if fitted else "no ABS"
		for part in ["FrontCaliper", "FrontCaliperRight", "RearCaliper", "FrontReservoir", "RearReservoir",
				"FrontMasterCylinder", "RearMasterCylinder", "FrontBrakeHose0", "RearBrakeHose0"]:
			check(brakes.has_node(part), "%s: %s is on the chassis" % [label, part])
		for caliper_name in ["FrontCaliper", "FrontCaliperRight", "RearCaliper"]:
			var caliper: Node3D = brakes.get_node(caliper_name)
			check(caliper.get_parent() == brakes, "%s: %s does not turn with the wheel" % [label, caliper_name])
			for piece in ["Half0", "Half1", "Bridge", "Mount"]:
				check(caliper.has_node(piece), "%s: %s has its %s" % [label, caliper_name, piece])
		check(brakes.has_node("ABSModule") == fitted, "%s: the ABS module follows the spec" % label)
		check(brakes.has_node("FrontABSSensor") == fitted and brakes.has_node("RearABSSensor") == fitted,
			"%s: the wheel-speed pickups follow the spec" % label)
		check(brakes.has_node("RearTorqueArm"), "%s: the rear caliper has a torque arm" % label)

		# twin front discs, one either side of the wheel; only the outboard one carries the tone ring
		check(bike._front_wheel.has_node("BrakeRotor") and bike._front_wheel.has_node("BrakeRotorRight"),
			"%s: the front wheel has two discs" % label)
		check(bike._front_wheel.has_node("RotorCarrier/ABSToneRing") == fitted,
			"%s: the front tone ring is on the outboard disc" % label)
		check(not bike._front_wheel.has_node("RotorCarrierRight/ABSToneRing"),
			"%s: only one front disc carries the ring" % label)
		check(bike._wheel_pivot.get_node("RotorCarrier").has_node("ABSToneRing") == fitted,
			"%s: the rear disc carries the ring" % label)

		# each caliper straddles its disc: the halves sit either side of the disc plane, on its edge
		for item in [["FrontCaliper", bike._front_wheel, "BrakeRotor", Drivetrain.FRONT_DISC_RADIUS],
				["FrontCaliperRight", bike._front_wheel, "BrakeRotorRight", Drivetrain.FRONT_DISC_RADIUS],
				["RearCaliper", bike._wheel_pivot, "BrakeRotor", Drivetrain.REAR_DISC_RADIUS]]:
			var disc := item[1] as Node3D
			var rotor := disc.get_node(item[2]) as Node3D
			var disc_x: float = rotor.global_position.x
			var half_a: float = (brakes.get_node("%s/Half0" % item[0]) as Node3D).global_position.x
			var half_b: float = (brakes.get_node("%s/Half1" % item[0]) as Node3D).global_position.x
			check((half_a - disc_x) * (half_b - disc_x) < 0.0,
				"%s: %s straddles its disc (halves at %.3f / %.3f, disc at %.3f)" % [label, item[0], half_a, half_b, disc_x])
			var axle: Vector3 = disc.global_position
			var centre: Vector3 = (brakes.get_node(item[0]) as Node3D).global_position
			var reach := Vector2(centre.y - axle.y, centre.z - axle.z).length()
			check(absf(reach - float(item[3])) < 0.03,
				"%s: %s sits on the disc's edge (%.3f vs radius %.3f)" % [label, item[0], reach, item[3]])

		# both front discs are the same size and symmetrically placed
		var left := (bike._front_wheel.get_node("BrakeRotor") as Node3D).position.x
		var right := (bike._front_wheel.get_node("BrakeRotorRight") as Node3D).position.x
		check(absf(left + right) < 1e-5, "%s: the front discs are symmetric about the wheel (%.3f / %.3f)" % [label, left, right])
		root.remove_child(bike)
		bike.free()
	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
