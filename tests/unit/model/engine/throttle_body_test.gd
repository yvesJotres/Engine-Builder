extends SceneTree

# The drawn throttle body has to be a throttle body, not a length of pipe: a motorcycle casting holds the butterfly, its
# shaft and the injector boss and stops there, so it comes out about 1.2 bores long (38 mm on a 32 mm bore). The old
# drawing used a fixed 60 mm, which is nearly two bores on a 250 and read as a bar. This also checks the body is shorter
# than the runner that feeds the valve, and that it still leaves room for the port-to-body joint.
# Run: godot --headless --path . -s tests/unit/geometry/throttle_body_test.gd (exit code 1 on failure)

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
	var checked := 0
	for name in Presets.PRESETS:
		var spec := spec_of(name)
		if spec.induction != "injection" or spec.stroke_type == "two_stroke":
			continue
		var model := EngineModel.new()
		root.add_child(model)
		model.build(spec)
		check(model._throttle_bodies.size() == spec.cylinders,
			"%s: one drawn throttle body per cylinder, got %d" % [name, model._throttle_bodies.size()])
		for body in model._throttle_bodies:
			var length: float = body.get_meta("length")
			var bore: float = body.get_meta("bore")
			var ratio := length / bore
			var mm := length * 100.0 # 1 scene unit = 10 cm
			var bore_mm := bore * 100.0
			check(ratio > 1.0 and ratio < 1.4,
				"%s: body is %.2f bores long (%.0f mm on a %.0f mm bore), not a pipe" % [name, ratio, mm, bore_mm])
			check(length < spec.runner_length_m * Units.M_TO_SCENE,
				"%s: the body (%.0f mm) is shorter than the runner it feeds (%.0f mm)" % [name, mm, spec.runner_length_m * 1000.0])
			check(length >= IntakeModel.BODY_LENGTH_MIN - 0.001 and length <= IntakeModel.BODY_LENGTH_MAX + 0.001,
				"%s: body length stays inside its limits (%.2f units)" % [name, length])
			checked += 1
		if name == "honda_cbr250rr":
			var first: Node3D = model._throttle_bodies[0]
			print("CBR250RR: bore %.0f mm, body %.0f mm (was 60 mm), %.2f bores, runner %.0f mm" % [
				first.get_meta("bore") * 100.0, first.get_meta("length") * 100.0,
				first.get_meta("length") / first.get_meta("bore"), spec.runner_length_m * 1000.0])
		root.remove_child(model)
		model.free()
	check(checked > 0, "at least one injected engine was checked")
	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
