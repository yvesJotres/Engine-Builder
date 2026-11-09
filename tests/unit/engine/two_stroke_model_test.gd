extends SceneTree

# The two-stroke drawing: the Yamaha RD350 is built without valves, cams or intake runners, has one exhaust port per cylinder, gets
# and its crank still turns the pistons. The ZX-25R four-stroke keeps its valves.
# Exits 1 on any failure. Run: godot --headless --path . -s res://tests/unit/engine/two_stroke_model_test.gd

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func _spec(name: String) -> EngineSpec:
	var spec := EngineSpec.new()
	var p: Dictionary = Presets.PRESETS[name]
	for key in p.keys():
		spec.set(key, p[key])
	return spec


func _meshes(node: Node) -> int:
	var n := 0
	for child in node.get_children():
		if child is MeshInstance3D:
			n += 1
		n += _meshes(child)
	return n


func _init() -> void:
	await process_frame
	var two := _spec("yamaha_rd350")
	check(two.stroke_type == "two_stroke", "the RD350 is a two-stroke")
	var model := EngineModel.new()
	root.add_child(model)
	model.build(two)
	check(model._valves.is_empty(), "two-stroke has no valves, got %d" % model._valves.size())
	check(model._cams.is_empty(), "two-stroke has no cams, got %d" % model._cams.size())
	check(model.exhaust_ports().size() == two.cylinders, "one exhaust port per cylinder, got %d" % model.exhaust_ports().size())
	check(model._pistons.size() == two.cylinders and model._rods.size() == two.cylinders, "a piston and rod per cylinder")
	var with_chamber := _meshes(model)
	# the chamber belongs to the exhaust layout, not the engine model: the model is the same with or without it
	var no_chamber := _spec("yamaha_rd350")
	no_chamber.expansion_chamber = false
	var bare := EngineModel.new()
	root.add_child(bare)
	bare.build(no_chamber)
	check(with_chamber == _meshes(bare), "the engine model does not draw the chamber, got a difference of %d" % (with_chamber - _meshes(bare)))
	# the crank still turns the pistons: their height changes with the crank angle
	var heights: Array[float] = []
	for deg in [0.0, 90.0, 180.0, 270.0]:
		model.update_crank(deg)
		heights.append(model._pistons[0].position.y)
	var spread := 0.0
	for h in heights:
		spread = maxf(spread, absf(h - heights[0]))
	check(spread > 0.01, "the piston moves with the crank, spread %.4f" % spread)
	model.free()
	bare.free()

	var four := _spec("kawasaki_zx25r")
	var model4 := EngineModel.new()
	root.add_child(model4)
	model4.build(four)
	check(model4._valves.size() > 0 and model4._cams.size() > 0, "the four-stroke keeps its valves and cams")
	model4.free()

	print("two_stroke_model_test: %s" % ("PASSED" if _fails == 0 else "FAILED"))
	quit(0 if _fails == 0 else 1)
