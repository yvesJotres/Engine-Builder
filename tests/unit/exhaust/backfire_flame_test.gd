extends SceneTree

# The exhaust side of a backfire: the flash at the tailpipe is sized by the energy the cylinder released, lives for a few
# tens of milliseconds, and draws nothing when the energy is zero (no pop, no flash). Before this, the only sign of a pop
# outside the sound was the word on the dash.
# Run: godot --headless --path . --quit-after 3000 -s res://tests/unit/exhaust/backfire_flame_test.gd

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func _init() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	await process_frame # the flash places itself in world space, which needs the node in the tree
	var flame := BackfireFlame.new()
	holder.add_child(flame)
	flame.build()
	flame.place(Vector3(1.0, 0.5, -2.0), Vector3(0.0, 0.0, -1.0))

	check(not flame.visible_now(), "nothing is drawn before a pop")
	flame.pop(0.0)
	check(not flame.visible_now(), "zero energy draws nothing")

	flame.pop(BackfireFlame.REFERENCE_J)
	var big := flame.radius()
	print("300 J pop: radius %.3f units, visible %s" % [big, str(flame.visible_now())])
	check(flame.visible_now(), "a reference pop is drawn")
	check(is_equal_approx(big, BackfireFlame.MAX_RADIUS), "a reference pop fills the max radius (%.3f)" % big)

	flame.update(BackfireFlame.POP_SECONDS * 0.5)
	print("half way through: visible %s" % str(flame.visible_now()))
	check(flame.visible_now(), "the flash survives half its life")
	flame.update(BackfireFlame.POP_SECONDS)
	check(not flame.visible_now(), "the flash is gone after its life")

	flame.pop(BackfireFlame.REFERENCE_J * 0.0625) # 18.75 J: a small engine's tick
	var small := flame.radius()
	print("18.75 J pop: radius %.3f units (%.0f%% of the 300 J one)" % [small, 100.0 * small / big])
	check(small < big * 0.75, "a small pop draws smaller than a big one (%.3f vs %.3f)" % [small, big])
	check(small >= BackfireFlame.MIN_RADIUS, "but never smaller than the floor (%.3f)" % small)

	# the flash sits outside the outlet, not inside the pipe
	flame.place(Vector3(1.0, 0.5, -2.0), Vector3(0.0, 0.0, -1.0))
	var away := flame.global_position.z
	print("placed at z=%.3f for an outlet at z=-2.000 pointing -Z" % away)
	check(away < -2.0, "the flash stands outside the outlet (%.3f < -2.000)" % away)

	flame.pop(BackfireFlame.REFERENCE_J)
	flame.update(BackfireFlame.POP_SECONDS + 0.1)
	check(not flame.visible_now(), "a forgotten flash fades out on its own")
	holder.free()

	print("backfire_flame_test: %s" % ("PASS" if _fails == 0 else "FAIL"))
	quit(0 if _fails == 0 else 1)
