extends SceneTree

# Prints every place the exhaust passes through the bike: the pipes are sampled along their centrelines against the frame
# capsules, the engine and tank boxes and the tyres. The measuring itself lives in scripts/model/pipe/exhaust_clearance.gd
# so this tool and the unit test agree.
# Run: godot --headless --path . -s res://tools/diagnostics/exhaust_clearance.gd [-- <preset_id>]

const PRESET := "honda_cbr1000rrr_sp"


func _init() -> void:
	await process_frame
	var id := PRESET
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and Presets.PRESETS.has(str(args[0])):
		id = str(args[0])
	var spec := EngineSpec.new()
	var preset: Dictionary = Presets.PRESETS[id]
	for key in preset.keys():
		spec.set(key, preset[key])

	var model := EngineModel.new()
	get_root().add_child(model)
	model.build(spec)
	# the bike is built exactly as main.gd builds it, or the clearances are measured against a different frame
	var tank_model := FuelTankModel.new()
	get_root().add_child(tank_model)
	tank_model.place(model.highest_y() + 0.4, (model.crank_position().z + model.throttle_position().z) * 0.5)
	var bounds: AABB = model.chassis_envelope()
	var half_width := maxf(0.85, maxf(absf(bounds.position.x), absf(bounds.end.x)) + 0.25)
	var dt := Drivetrain.new()
	get_root().add_child(dt)
	dt.build(Ground.Y, GearboxModel.countershaft_position(model.crank_position(), spec), tank_model.outlet_position(),
		half_width, spec.abs_hardware(), bounds, spec, id)
	var layout := ExhaustLayout.build(spec, model.exhaust_ports(), model.crank_position(), Ground.Y, dt.rear_axle)
	await process_frame

	var tank_bounds := AABB()
	var tank_node := dt.get_node_or_null("Chassis/Tank") as Node3D
	if tank_node != null:
		tank_bounds = _node_aabb(tank_node)

	var result := ExhaustClearance.check(dt, bounds, tank_bounds, layout)
	var worst: Dictionary = result["worst"]
	if worst.is_empty():
		print("%s: no exhaust part passes through the frame, the engine, the tank or a tyre" % id)
	else:
		var keys := worst.keys()
		keys.sort_custom(func(x, y): return worst[x] > worst[y])
		for key in keys:
			print("%s: %-40s %5.0f mm" % [id, key, worst[key] * 100.0])
	print("%s: penetrating samples %d" % [id, result["samples"]])
	quit(0)


func _node_aabb(node: Node3D) -> AABB:
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
