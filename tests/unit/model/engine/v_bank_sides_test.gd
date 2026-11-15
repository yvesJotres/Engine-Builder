extends SceneTree

# A V engine breathes from the valley and exhausts outwards. In the drawing that means every bank's intake port and
# runner sit on the inboard face of its head - the side facing the other bank - and its exhaust port on the outboard
# face, which is where a real engine's headers leave (the reason the pipe on a V-twin sweeps down the outside of the
# bike rather than growing out of the middle of the engine).
# Run: godot --headless --path . -s tests/unit/geometry/v_bank_sides_test.gd (exit code 1 on failure)

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func spec_of(id: String) -> EngineSpec:
	var spec := EngineSpec.new()
	var preset: Dictionary = Presets.PRESETS[id]
	for key in preset.keys():
		spec.set(key, preset[key])
	return spec


func _init() -> void:
	await process_frame
	var v_engines := 0
	for name in Presets.PRESETS:
		var spec := spec_of(name)
		if spec.layout != "V" or spec.stroke_type == "two_stroke":
			continue
		v_engines += 1
		var model := EngineModel.new()
		root.add_child(model)
		model.build(spec)
		check(model._banks.size() == spec.cylinders, "%s: one bank per cylinder" % name)
		# "outboard" is the side the bank leans towards: forward for a bank that leans forward, backward for the other,
		# so the valley stays between them. Measured in model space against the cylinder's own axis (a piston sits on it).
		var levers: Array[float] = []
		for i in mini(spec.cylinders, mini(model._ports.size(), model._intake_mouths.size())):
			var bank: Node3D = model._banks[i]
			var out := 1.0 if sin(bank.rotation.x) >= 0.0 else -1.0
			levers.append(bank.rotation.x)
			var axis_z: float = model.to_local(model._pistons[i].global_position).z # a point on the bore axis
			var port: Vector3 = model._ports[i]
			var mouth: Vector3 = model._intake_mouths[i]
			var bore: float = spec.bore_mm * Units.MM_TO_SCENE
			check((port.z - axis_z) * out > bore * 0.25,
				"%s: cylinder %d exhausts outboard (%.2f units that way)" % [name, i + 1, (port.z - axis_z) * out])
			check((mouth.z - axis_z) * out < -bore * 0.25,
				"%s: cylinder %d breathes from the valley (%.2f units inboard)" % [name, i + 1, (mouth.z - axis_z) * out])
		# the two banks lean opposite ways, so the two banks' exhausts leave on opposite sides of the engine
		if levers.size() >= 2:
			check(signf(sin(levers[0])) != signf(sin(levers[1])),
				"%s: the banks lean to opposite sides" % name)
			check(absf(levers[0] + levers[1]) < 0.01, "%s: the banks are symmetric about the vertical" % name)
		root.remove_child(model)
		model.free()
	check(v_engines > 0, "the preset list holds a V engine to check")

	# an upright engine has no valley: the exhaust stays on the front and the intake on the back
	var inline := spec_of("honda_cbr250rr")
	var inline_model := EngineModel.new()
	root.add_child(inline_model)
	inline_model.build(inline)
	var bore := inline.bore_mm * Units.MM_TO_SCENE
	var inline_axis: float = inline_model.to_local(inline_model._pistons[0].global_position).z
	check(inline_model._ports[0].z - inline_axis > bore * 0.25,
		"an upright cylinder exhausts to the front (%.2f units)" % (inline_model._ports[0].z - inline_axis))
	check(inline_model._intake_mouths[0].z - inline_axis < -bore * 0.25,
		"and breathes from the back (%.2f units)" % (inline_model._intake_mouths[0].z - inline_axis))

	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
