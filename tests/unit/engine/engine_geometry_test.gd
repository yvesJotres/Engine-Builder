extends SceneTree

# Checks every preset's drawing against its fire angles: each piston is at top dead centre at its fire angle, and each rod's
# crank end sits on its crank pin as the crank turns (pin angle = bank angle + fire - crank, the crank turns the way engine-sim does).
# Run: godot --headless -s tests/unit/engine/engine_geometry_test.gd (exit code 1 on failure)

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func _init() -> void:
	await process_frame
	for name in Presets.PRESETS:
		var spec := EngineSpec.new()
		var preset: Dictionary = Presets.PRESETS[name]
		for key in preset:
			spec.set(key, preset[key])
		var model := EngineModel.new()
		root.add_child(model)
		model.build(spec)
		var fire := FiringOrders.for_spec(spec)
		var centre := Vector3(0.0, model._crank_y, 0.0)
		var n := spec.cylinders
		if spec.layout == "W":
			check(n == 16 and model._pistons.size() == 16, "%s: all W16 cylinders are built" % name)
			check(model._pin_x[0] == model._pin_x[3] and model._pin_x[4] != model._pin_x[0], "%s: W cylinders occupy four axial stations" % name)
		var bank_deg: Array[float] = []
		for i in n:
			for ring_index in 3:
				check(model._pistons[i].has_node("PistonRing%d" % ring_index), "%s: cylinder %d has piston ring %d" % [name, i + 1, ring_index + 1])
			# the piston's bank angle from vertical, read where its piston is at top dead centre
			model.update_crank(fire[i])
			var p := model.to_local(model._pistons[i].global_position) - centre
			bank_deg.append(rad_to_deg(atan2(p.z, p.y)))
			var best_c := 0.0
			var best_y := -1e9
			for step in 1440:
				var c := step * 0.5
				model.update_crank(c)
				var y: float = model._pistons[i].global_position.y
				if y > best_y:
					best_y = y
					best_c = c
			var d := fposmod(best_c - fire[i] + 180.0, 360.0) - 180.0
			check(absf(d) <= 1.0, "%s: cylinder %d top dead centre %.1f, fire %.0f" % [name, i + 1, best_c, fire[i]])
		for c in [0.0, 100.0, 333.0, 600.0]:
			model.update_crank(c)
			for i in n:
				var wrist: Vector3 = model.to_local(model._pistons[i].global_position)
				var rod_mid: Vector3 = model.to_local(model._rods[i].global_position)
				var pin := 2.0 * rod_mid - wrist - centre
				var pin_deg := fposmod(rad_to_deg(atan2(pin.z, pin.y)), 360.0)
				var expected := fposmod(-c + bank_deg[i] + fire[i], 360.0)
				var d := fposmod(pin_deg - expected + 180.0, 360.0) - 180.0
				check(absf(d) <= 1.0, "%s: cylinder %d rod off its crank pin at crank %.0f (pin %.1f, expected %.1f)" % [name, i + 1, c, pin_deg, expected])
		root.remove_child(model)
		model.free()
		print("%s: %d cylinders checked" % [name, n])
	var drivetrain := Drivetrain.new()
	root.add_child(drivetrain)
	drivetrain.build(Ground.Y, Vector3.ZERO, Vector3(0.0, 4.0, 0.0), 1.5)
	for wheel in [drivetrain._front_wheel, drivetrain._wheel_pivot]:
		var tyre := wheel.get_node("Tyre") as MeshInstance3D
		var mesh := tyre.mesh as TorusMesh
		var width := 100.0 if wheel == drivetrain._front_wheel else Drivetrain.TIRE_WIDTH_MM
		check(absf(mesh.inner_radius - Drivetrain.RIM_DIAMETER_MM * 0.5 * Drivetrain.MM) < 0.001, "wheel rim matches the 17-inch diameter")
		check(absf((mesh.outer_radius - mesh.inner_radius) * tyre.scale.y - width * Drivetrain.MM) < 0.001, "tyre width matches its specification")
		check(wheel.has_node("BrakeRotor"), "brake rotor is attached to its rotating wheel")
	check(drivetrain.has_node("Chassis/ForkLower-1") and drivetrain.has_node("Chassis/ForkLower1"), "front forks are attached to the chassis")
	check(drivetrain.has_node("Chassis/Swingarm-1") and drivetrain.has_node("Chassis/Swingarm1"), "rear swingarm is attached to the chassis")
	check(drivetrain.has_node("Chassis/TankMount-1") and drivetrain.has_node("Chassis/TankMount1"), "tank rails are supported by the frame")
	var frame_side := drivetrain.get_node("Chassis/FrameDown1") as MeshInstance3D
	check(absf(frame_side.position.x - 1.5) < 0.001, "frame width accommodates wider engines")
	check(drivetrain.has_node("Chassis/Seat") and drivetrain.has_node("Chassis/Handlebar"), "seat and handlebar are attached to the chassis")
	check(drivetrain.has_node("Chassis/ShockBody") and drivetrain.has_node("Chassis/ShockRod"), "rear shock connects the frame and swingarm")
	drivetrain.update(0.0, 60.0, 0.25)
	check(absf(drivetrain._wheel_pivot.rotation.x) > 0.1 and absf(drivetrain._front_wheel.rotation.x) > 0.1, "both detailed wheels rotate")
	drivetrain.free()
	var tank := FuelTankModel.new()
	root.add_child(tank)
	tank.update(0.0, Color.BLUE)
	var empty_height := tank._level_mesh.height
	tank.update(1.0, Color.BLUE)
	check(tank._level_mesh.height > empty_height, "fuel sight gauge follows fuel level")
	check(tank.has_node("TankShell"), "tank has a shaped shell")
	tank.free()
	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
