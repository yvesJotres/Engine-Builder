extends SceneTree

# A triple clamp has to actually clamp: four bosses, one per fork tube per yoke, bored along the leg, sitting on the leg
# it grips, carrying pinch bolts. A yoke slab on its own is a plate floating over the fork.
# Run: godot --headless --path . -s tests/unit/drivetrain/fork_clamp_test.gd

var _fails := 0
var _checks := 0


func check(ok: bool, msg: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func _init() -> void:
	await process_frame
	var spec := EngineSpec.new()
	var preset: Dictionary = Presets.PRESETS["honda_cbr1000rrr_sp"]
	for key in preset.keys():
		spec.set(key, preset[key])
	var dt := Drivetrain.new()
	root.add_child(dt)
	dt.build(Ground.Y, Vector3(0.0, 0.9, -0.5), Vector3(0.0, 4.0, -1.0), 1.1, true, AABB(), spec, "honda_cbr1000rrr_sp")
	await process_frame

	var cockpit := dt.get_node_or_null("Cockpit") as Node3D
	check(cockpit != null, "the cockpit is built")
	if cockpit == null:
		_finish()
		return

	for yoke in ["Top", "Bottom"]:
		for pair in [["Left", -1], ["Right", 1]]:
			var tag: String = pair[0]
			var side: int = pair[1]
			var clamp_node := cockpit.get_node_or_null("ForkClamp%s%s" % [yoke, tag]) as Node3D
			check(clamp_node != null, "%s%s clamp exists" % [yoke, tag])
			if clamp_node == null:
				continue

			# it sits on the leg it grips
			var leg := dt.get_node_or_null("Chassis/ForkUpper%d" % side) as MeshInstance3D
			check(leg != null, "%s%s: the leg it clamps is drawn" % [yoke, tag])
			if leg != null:
				var shape := leg.mesh as CylinderMesh
				var axis: Vector3 = (leg.global_transform.basis * Vector3.UP).normalized()
				var half: float = shape.height * 0.5
				var d := _point_segment(clamp_node.global_position, leg.global_position - axis * half,
					leg.global_position + axis * half)
				check(d < 0.03, "%s%s: the clamp centre is %.3f off the leg axis" % [yoke, tag, d])
				check(absf(clamp_node.global_transform.basis.y.normalized().dot(axis)) > 0.99,
					"%s%s: the clamp is not bored along the leg" % [yoke, tag])
				check(shape.top_radius < 0.10, "%s%s: the leg is %.2f across, so it is the tube being clamped" % [yoke, tag, shape.top_radius])

			var boss := clamp_node.get_node_or_null("Boss") as MeshInstance3D
			check(boss != null, "%s%s: the clamp has a boss" % [yoke, tag])
			if boss != null:
				var boss_shape := boss.mesh as CylinderMesh
				check(boss_shape.top_radius > 0.09 + 0.05,
					"%s%s: the boss (%.2f) does not reach round the tube (0.09)" % [yoke, tag, boss_shape.top_radius])
				check(boss_shape.height >= 0.24, "%s%s: the boss is only %.2f tall" % [yoke, tag, boss_shape.height])

			for bolt_index in 2:
				var bolt := clamp_node.get_node_or_null("PinchBolt%d" % bolt_index) as MeshInstance3D
				check(bolt != null, "%s%s: pinch bolt %d" % [yoke, tag, bolt_index])
				if bolt != null:
					# the bolt runs across the clamp face, not along the leg
					var along_leg := absf(bolt.global_transform.basis.y.normalized().dot(clamp_node.global_transform.basis.y.normalized()))
					check(along_leg < 0.2, "%s%s: pinch bolt %d points along the leg" % [yoke, tag, bolt_index])

			# and it sits at the front of the bike, where the face of a clamp is
			check(clamp_node.global_position.z > dt._head.z - 0.5,
				"%s%s: the clamp is behind the steering head" % [yoke, tag])

	var top := cockpit.get_node_or_null("ForkClampTopLeft") as Node3D
	var bottom := cockpit.get_node_or_null("ForkClampBottomLeft") as Node3D
	if top != null and bottom != null:
		check(top.global_position.y > bottom.global_position.y + 0.20,
			"the top clamp should sit well above the bottom one (%.2f vs %.2f)" % [top.global_position.y, bottom.global_position.y])

	print("clamps: %d, boss above the tube, bolts across the face" % 4)
	_finish()


func _finish() -> void:
	print("RESULT: " + ("PASS" if _fails == 0 else "%d of %d failed" % [_fails, _checks]))
	quit(0 if _fails == 0 else 1)


func _point_segment(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var denom := ab.dot(ab)
	if denom < 1e-12:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / denom, 0.0, 1.0)
	return p.distance_to(a + ab * t)
