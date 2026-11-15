extends SceneTree

# Both wheels turn on a spindle, and the spindle belongs to the bike: it is centred on the axle, lies across the machine,
# and reaches out to the fork legs at the front and the swingarm arms at the back. A nut holds it in on one end.
# Run: godot --headless --path . -s tests/unit/drivetrain/axle_test.gd

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


# Half the length of a cylinder laid across the bike, and the radius it was drawn at.
func measure(mi: MeshInstance3D) -> Dictionary:
	var shape := mi.mesh as CylinderMesh
	var length: float = shape.height * absf(mi.scale.x) * absf(mi.global_transform.basis.x.length())
	return {"radius": shape.top_radius, "half_length": length * 0.5}


func _init() -> void:
	await process_frame
	var spec := EngineSpec.new()
	var preset: Dictionary = Presets.PRESETS["honda_cbr1000rrr_sp"]
	for key in preset.keys():
		spec.set(key, preset[key])
	var bike := Drivetrain.new()
	root.add_child(bike)
	bike.build(0.0, Vector3(0.0, 2.0, 0.0), Vector3(0.0, 4.0, 0.0), 0.85, true, AABB(), spec)
	var axles := bike.get_node_or_null("Axles")
	check(axles != null, "the bike has axle spindles")
	if axles == null:
		print("RESULT: FAIL")
		quit(1)
		return
	for item in [["Front", bike._front_wheel, Drivetrain.AXLE_FRONT_RADIUS], ["Rear", bike._wheel_pivot, Drivetrain.AXLE_REAR_RADIUS]]:
		var tag: String = item[0]
		var wheel: Node3D = item[1]
		var shaft := axles.get_node_or_null("%sAxle" % tag) as MeshInstance3D
		check(shaft != null, "%s: the wheel has an axle" % tag)
		if shaft == null:
			continue
		check(shaft.get_parent() == axles and not wheel.is_ancestor_of(shaft),
			"%s: the axle belongs to the bike, not to the wheel it carries" % tag)
		# centred on the axle, lying across the machine
		var at := shaft.global_position
		check(Vector2(at.y - wheel.global_position.y, at.z - wheel.global_position.z).length() < 1e-4,
			"%s: the axle is centred on the wheel's axle line (%.3f, %.3f vs %.3f, %.3f)" % [
				tag, at.y, at.z, wheel.global_position.y, wheel.global_position.z])
		check(absf(shaft.rotation.z - PI * 0.5) < 1e-4, "%s: the axle lies across the bike, not along it" % tag)
		var size := measure(shaft)
		check(absf(size.radius - float(item[2])) < 1e-4,
			"%s: the axle is %.0f mm in diameter" % [tag, size.radius * 200.0])
		check(size.half_length >= Drivetrain.FORK_LEG_OFFSET * 0.9,
			"%s: the axle reaches out to the mounts (%.0f mm from the centre line)" % [tag, size.half_length * 100.0])
		# a nut at one end, a washer under it, and the hollow bore showing at both ends
		check(axles.has_node("%sAxleNut" % tag), "%s: the axle has a nut" % tag)
		check(axles.has_node("%sAxleWasher" % tag), "%s: the nut has a washer under it" % tag)
		check(axles.has_node("%sAxleBore0" % tag) and axles.has_node("%sAxleBore1" % tag),
			"%s: the spindle is drawn hollow at both ends" % tag)
		var nut := axles.get_node("%sAxleNut" % tag) as Node3D
		check(absf(nut.global_position.x) > size.half_length,
			"%s: the nut sits outside the clamp, not inside the hub" % tag)
		print("%s axle: Ø %.0f mm, %.0f mm long, nut at x %.3f" % [
			tag, size.radius * 200.0, size.half_length * 200.0, nut.global_position.x])

	# the front axle spans the fork legs, the rear spans the swingarm arms
	var fork_left: Vector3 = (bike.get_node("Chassis/ForkLower-1") as Node3D).global_position
	var front := axles.get_node("FrontAxle") as MeshInstance3D
	var front_half: float = measure(front).half_length
	check(absf(front_half - absf(fork_left.x)) < 0.06,
		"the front axle ends at the fork legs (axle %.3f, leg %.3f)" % [front_half, absf(fork_left.x)])
	var rear_half: float = measure(axles.get_node("RearAxle") as MeshInstance3D).half_length
	check(rear_half > front_half, "the rear axle is the longer one (%.3f vs %.3f)" % [rear_half, front_half])

	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
