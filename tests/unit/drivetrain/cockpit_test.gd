extends SceneTree

# The steering head and the rider's controls: two yokes clamping both fork tubes with the stem nut between them, a clip-on
# per side swept back to the grips, a throttle tube that twists, and levers that swing in when they are pulled.
# Run: godot --headless --path . -s tests/unit/drivetrain/cockpit_test.gd

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func _init() -> void:
	await process_frame
	var bike := Drivetrain.new()
	root.add_child(bike)
	bike.build(0.0, Vector3(0.0, 2.0, 0.0), Vector3(0.0, 4.0, 0.0), 0.85, true)
	var cockpit := bike.get_node_or_null("Cockpit")
	check(cockpit != null, "the bike has a steering head")
	if cockpit == null:
		print("RESULT: FAIL")
		quit(1)
		return

	# ---- the yokes ----
	var top := cockpit.get_node_or_null("TopYoke") as MeshInstance3D
	var bottom := cockpit.get_node_or_null("BottomYoke") as MeshInstance3D
	check(top != null and bottom != null, "both yokes are there, not just the top one")
	if top != null and bottom != null:
		var top_size := (top.mesh as BoxMesh).size
		var bottom_size := (bottom.mesh as BoxMesh).size
		var leg_x: float = bike._front_half + Drivetrain.FORK_LEG_OFFSET
		check(top_size.x >= leg_x * 2.0, "the top yoke reaches across both fork tubes (%.2f wide, tubes at ±%.2f)" % [top_size.x, leg_x])
		check(top_size.y < top_size.x and top_size.y < top_size.z, "the yoke is a flat plate, not a cube")
		check(bottom.global_position.y < top.global_position.y, "the bottom yoke sits below the top one")
		check(bottom_size.x <= top_size.x, "the bottom yoke is no wider than the top")
		# both yokes are centred on the steering head, on the same axis
		check(Vector2(top.global_position.x, top.global_position.z).distance_to(Vector2(bottom.global_position.x, bottom.global_position.z)) < 0.10,
			"the yokes share the steering axis")
		print("yokes: top %.2f x %.2f x %.2f at y %.2f, bottom at y %.2f" % [
			top_size.x, top_size.y, top_size.z, top.global_position.y, bottom.global_position.y])
	check(cockpit.has_node("SteeringStemNut"), "the steering stem nut sits in the top yoke")

	# ---- the clip-ons ----
	for side in [["Left", -1.0], ["Right", 1.0]]:
		var tag: String = side[0]
		var sign_x: float = side[1]
		var bar := cockpit.get_node_or_null("ClipOn" + tag) as MeshInstance3D
		var clamp := cockpit.get_node_or_null("ClipOnClamp" + tag) as MeshInstance3D
		check(bar != null and clamp != null, "%s: the clip-on and its clamp on the fork tube" % tag)
		if bar == null:
			continue
		var length: float = (bar.mesh as CylinderMesh).height
		check(length > 2.0, "%s: the bar is a real clip-on length (%.0f mm)" % [tag, length * 100.0])
		check(absf((bar.mesh as CylinderMesh).top_radius - Drivetrain.BAR_RADIUS) < 1e-4,
			"%s: the bar is %.0f mm across" % [tag, (bar.mesh as CylinderMesh).top_radius * 200.0])
		var dir: Vector3 = (bar.global_transform.basis.y).normalized() * 1.0
		var start: Vector3 = bar.global_position - dir * length * 0.5
		var end: Vector3 = bar.global_position + dir * length * 0.5
		check(dir.z < -0.25 and absf(dir.x) > absf(dir.z),
			"%s: the bar runs outward and back to the rider (x %.2f, z %.2f)" % [tag, dir.x, dir.z])
		check(absf(end.x) > absf(start.x), "%s: the bar runs out from the fork tube, so the grips are wider than the tubes" % tag)
		check(sign_x * clamp.global_position.x > 0.0, "%s: the clamp is on its own fork tube" % tag)
		print("%s clip-on: %.0f mm long, from x %.2f to %.2f, swept %.0f deg" % [
			tag, length * 100.0, start.x, end.x, rad_to_deg(acos(clampf(-dir.z, -1.0, 1.0)))])
	# a bike's bars are about 700 mm across: the grips must not end up near the centre line
	var left_grip: Vector3 = (cockpit.get_node("Grip") as Node3D).global_position
	var right_grip: Vector3 = (cockpit.get_node("ThrottleGrip") as Node3D).global_position
	var bar_width := left_grip.distance_to(right_grip)
	check(bar_width > 6.0 and bar_width < 8.0, "the bars are %.0f mm across, as a bike's are" % (bar_width * 100.0))
	print("bars: %.0f mm wide, grips at ±%.0f mm" % [bar_width * 100.0, absf(left_grip.x) * 100.0])
	check(cockpit.has_node("ThrottleGrip/ThrottleTube/Grip"), "the right grip is on the throttle tube")
	check(cockpit.has_node("Grip"), "the left grip is on the bar")
	check(cockpit.has_node("ForkCapLeft") and cockpit.has_node("ForkCapRight"), "both fork tops are capped")

	# ---- the levers move with the rider ----
	var brake := cockpit.get_node_or_null("FrontBrakeLever") as Node3D
	var clutch := cockpit.get_node_or_null("ClutchLever") as Node3D
	var tube := cockpit.get_node_or_null("ThrottleGrip/ThrottleTube") as Node3D
	check(brake != null and clutch != null and tube != null, "brake lever, clutch lever and throttle tube")
	if brake == null or clutch == null or tube == null:
		print("RESULT: FAIL")
		quit(1)
		return
	check(brake.global_position.x > 0.0 and clutch.global_position.x < 0.0, "brake on the right, clutch on the left")
	# the master cylinder and its reservoir: on the right bar, with the reservoir standing clear above it
	var master := bike.get_node_or_null("BrakeHardware/FrontMasterCylinder") as Node3D
	var reservoir := bike.get_node_or_null("BrakeHardware/FrontReservoir") as Node3D
	check(master != null and reservoir != null, "the front master cylinder has a reservoir")
	if master != null and reservoir != null:
		check(reservoir.global_position.y > master.global_position.y + 0.15,
			"the reservoir stands above the master cylinder (%.2f vs %.2f)" % [reservoir.global_position.y, master.global_position.y])
		check(reservoir.global_position.distance_to(master.global_position) > 0.2,
			"the reservoir is a separate part, not buried in the master body")
		check(master.global_position.x > 0.0, "the master cylinder is clamped to the right-hand bar")
		check(master.global_position.distance_to(brake.global_position) < 0.5,
			"the master sits at the lever perch (%.2f away)" % master.global_position.distance_to(brake.global_position))
	check(absf(brake.rotation.y) < 1e-6 and absf(tube.rotation.y) < 1e-6, "released: lever and grip sit at rest (%f, %f)" % [brake.rotation.y, tube.rotation.y])

	# where the blade tip sits with the lever at rest, so the pull can be measured against it
	var blade := brake.get_node("Blade") as MeshInstance3D
	var blade_length: float = (blade.mesh as CylinderMesh).height
	var rest_tip: Vector3 = brake.global_position + (blade.global_position - brake.global_position) * 2.0
	# pull everything in
	bike.update(0.0, 60.0, 1.0 / 60.0, 1.0, 1.0, 1.0)
	check(absf(brake.rotation.y - Drivetrain.LEVER_TRAVEL) < 1e-5,
		"the front brake lever swings %.0f deg when pulled right in (%.3f)" % [rad_to_deg(Drivetrain.LEVER_TRAVEL), brake.rotation.y])
	check(absf(clutch.rotation.y + Drivetrain.LEVER_TRAVEL) < 1e-5,
		"the clutch lever swings the other way, towards its own grip (%.3f)" % clutch.rotation.y)
	check(absf(tube.rotation.y + Drivetrain.THROTTLE_TWIST) < 1e-5,
		"the throttle tube twists %.0f deg at full throttle (%.3f)" % [rad_to_deg(Drivetrain.THROTTLE_TWIST), tube.rotation.y])
	# the blade is a lever's length, and pulling it draws the tip back towards the bar rather than away from it
	check(absf(blade_length - Drivetrain.LEVER_LENGTH) < 0.02,
		"the lever is %.0f mm from pivot to tip" % (blade_length * 100.0))
	var tip: Vector3 = brake.global_position + (blade.global_position - brake.global_position) * 2.0
	check(tip.z < rest_tip.z - 0.15,
		"pulling draws the lever tip back towards the bar (z %.2f from %.2f)" % [tip.z, rest_tip.z])

	# half a pull moves it half way, and releasing puts it back
	bike.update(0.0, 60.0, 1.0 / 60.0, 0.5, 0.5, 0.5)
	check(absf(brake.rotation.y - Drivetrain.LEVER_TRAVEL * 0.5) < 1e-5, "half a lever pull moves it half way")
	bike.update(0.0, 60.0, 1.0 / 60.0, 0.0, 0.0, 0.0)
	check(absf(brake.rotation.y) < 1e-6 and absf(tube.rotation.y) < 1e-6, "releasing lets the lever and grip back out")

	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
