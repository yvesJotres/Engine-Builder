extends SceneTree

# Checks every preset's drawing against its fire angles: each piston is at top dead centre at its fire angle, and each rod's
# crank end sits on its crank pin as the crank turns (pin angle = bank angle + fire - crank, the crank turns the way engine-sim does).
# Run: godot --headless -s tests/engine_geometry_test.gd (exit code 1 on failure)

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func _init() -> void:
	await process_frame
	for name in Presets.PRESETS:
		var spec := EngineSpec.new()
		var preset: Dictionary = Presets.PRESETS[name]
		for key in preset:
			spec.set(key, preset[key])
		var model := EngineModel.new()
		root.add_child(model)
		model.build(spec)
		var fire := FiringOrders.for_spec(spec)
		var centre := Vector3(0.0, model._crank_y, 0.0)
		var n := spec.cylinders
		var bank_deg: Array[float] = []
		for i in n:
			# the piston's bank angle from vertical, read where its piston is at top dead centre
			model.update_crank(fire[i])
			var p := model.to_local(model._pistons[i].global_position) - centre
			bank_deg.append(rad_to_deg(atan2(p.z, p.y)))
			var best_c := 0.0
			var best_y := -1e9
			for step in 1440:
				var c := step * 0.5
				model.update_crank(c)
				var y: float = model._pistons[i].global_position.y
				if y > best_y:
					best_y = y
					best_c = c
			var d := fposmod(best_c - fire[i] + 180.0, 360.0) - 180.0
			check(absf(d) <= 1.0, "%s: cylinder %d top dead centre %.1f, fire %.0f" % [name, i + 1, best_c, fire[i]])
		for c in [0.0, 100.0, 333.0, 600.0]:
			model.update_crank(c)
			for i in n:
				var wrist: Vector3 = model.to_local(model._pistons[i].global_position)
				var rod_mid: Vector3 = model.to_local(model._rods[i].global_position)
				var pin := 2.0 * rod_mid - wrist - centre
				var pin_deg := fposmod(rad_to_deg(atan2(pin.z, pin.y)), 360.0)
				var expected := fposmod(-c + bank_deg[i] + fire[i], 360.0)
				var d := fposmod(pin_deg - expected + 180.0, 360.0) - 180.0
				check(absf(d) <= 1.0, "%s: cylinder %d rod off its crank pin at crank %.0f (pin %.1f, expected %.1f)" % [name, i + 1, c, pin_deg, expected])
		root.remove_child(model)
		model.free()
		print("%s: %d cylinders checked" % [name, n])
	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
