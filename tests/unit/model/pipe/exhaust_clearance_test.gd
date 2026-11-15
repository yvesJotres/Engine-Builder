extends SceneTree

# Nothing the exhaust is drawn with may pass through the bike: not the headers, not the collector, not the canister, not
# the tailpipe. The pipes are sampled along their centrelines against the frame capsules (every structural member is a
# cylinder), the engine and tank boxes and the tyres. An inline engine and a V engine are both checked, because the V's
# rear bank has to thread past the swingarm pivot and the rear tyre.
# Run: godot --headless --path . -s tests/unit/model/pipe/exhaust_clearance_test.gd

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func _init() -> void:
	await process_frame
	for id in ["honda_cbr1000rrr_sp", "ducati_panigale_v4"]:
		var spec := EngineSpec.new()
		var preset: Dictionary = Presets.PRESETS[id]
		for key in preset.keys():
			spec.set(key, preset[key])

		var model := EngineModel.new()
		root.add_child(model)
		model.build(spec)
		var tank := FuelTankModel.new()
		root.add_child(tank)
		tank.place(model.highest_y() + 0.4, (model.crank_position().z + model.throttle_position().z) * 0.5)
		var bounds: AABB = model.chassis_envelope()
		var half_width := maxf(0.85, maxf(absf(bounds.position.x), absf(bounds.end.x)) + 0.25)
		var dt := Drivetrain.new()
		root.add_child(dt)
		dt.build(Ground.Y, GearboxModel.countershaft_position(model.crank_position(), spec), tank.outlet_position(),
			half_width, spec.abs_hardware(), bounds, spec, id)
		var layout := ExhaustLayout.build(spec, model.exhaust_ports(), model.crank_position(), Ground.Y, dt.rear_axle)
		await process_frame

		var tank_bounds := _node_aabb(dt.get_node_or_null("Chassis/Tank") as Node3D)
		var result := ExhaustClearance.check(dt, bounds, tank_bounds, layout)
		var worst: Dictionary = result["worst"]
		var keys := worst.keys()
		keys.sort_custom(func(x, y): return worst[x] > worst[y])
		var summary := "none"
		if not keys.is_empty():
			summary = "%s %.0f mm" % [keys[0], worst[keys[0]] * 100.0]
		check(worst.is_empty(), "%s: the exhaust clears the bike, worst is %s" % [id, summary])
		print("%s: %d pipes, worst clip %s" % [id, layout.pipes.size(), summary])

		model.queue_free()
		tank.queue_free()
		dt.queue_free()

	print("RESULT: " + ("PASS" if _fails == 0 else "%d of %d failed" % [_fails, 2]))
	quit(0 if _fails == 0 else 1)


func _node_aabb(node: Node3D) -> AABB:
	if node == null:
		return AABB()
	var out := AABB()
	var first := true
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := mi as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var box: AABB = mesh_instance.global_transform * mesh_instance.mesh.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out
