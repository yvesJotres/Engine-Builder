extends SceneTree

func _init() -> void:
	await process_frame
	var tested := 0
	for name in Presets.PRESETS:
		var spec := EngineSpec.new()
		for key in Presets.PRESETS[name]:
			spec.set(key, Presets.PRESETS[name][key])
		if spec.vehicle_type == "car":
			continue
		var engine := EngineModel.new()
		root.add_child(engine)
		engine.build(spec)
		var box := engine.chassis_envelope()
		assert(box.has_volume(), "%s has no exterior envelope" % name)
		var bike := Drivetrain.new()
		root.add_child(bike)
		var countershaft := GearboxModel.countershaft_position(engine.crank_position(), spec)
		bike.build(Ground.Y, countershaft, Vector3(0, engine.highest_y() + 0.4, 0), 0.85, spec.has_abs, box)
		var upright := bike.get_node("Chassis/FrameDown1") as MeshInstance3D
		assert(upright.position.x >= box.end.x + 0.24, "%s: frame too narrow" % name)
		assert(upright.position.z <= box.position.z - 0.24, "%s: upright inside engine" % name)
		var top := bike.get_node("Chassis/FrameTop1") as MeshInstance3D
		assert(top.position.y + absf((top.quaternion * Vector3.UP).y) * (top.mesh as CylinderMesh).height * 0.5 >= box.end.y, "%s: frame too low" % name)
		bike.free()
		engine.free()
		tested += 1
	print("adaptive chassis: PASS (%d motorcycle presets)" % tested)
	quit()
