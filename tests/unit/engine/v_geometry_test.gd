extends SceneTree

# Checks the drawn Panigale V4 against the simulation and engine-sim's panigale_v4.mr:
# each piston is at top dead centre at its fire angle, wires 1 and 3 sit on the -45 degree bank and wires 2 and 4 on +45,
# and the four cylinders share two crank pins.
# Run: godot --headless -s tests/unit/engine/v_geometry_test.gd (exit code 1 on failure)

var _fails := 0


func check(ok: bool, msg: String) -> void:
	print(("ok   " if ok else "FAIL ") + msg)
	if not ok:
		_fails += 1


func _init() -> void:
	await process_frame
	var spec := EngineSpec.new()
	var preset: Dictionary = Presets.PRESETS["ducati_panigale_v4"]
	for key in preset:
		spec.set(key, preset[key])
	var model := EngineModel.new()
	root.add_child(model)
	model.build(spec)
	var fire := FiringOrders.for_spec(spec)
	var centre := Vector3(0.0, model._crank_y, 0.0) # crank centre, in the model's own space
	var angles := [0.0, 0.0, 0.0, 0.0]
	for i in 4:
		var best_c := 0.0
		var best_y := -1e9
		for step in 1440: # half-degree steps through one 720 degree cycle
			var c := step * 0.5
			model.update_crank(c)
			var y: float = model._pistons[i].global_position.y
			if y > best_y:
				best_y = y
				best_c = c
		var d := fposmod(best_c - fire[i] + 180.0, 360.0) - 180.0
		check(absf(d) <= 1.0, "cylinder %d at top dead centre at its fire angle %.0f (peak at %.1f)" % [i + 1, fire[i], best_c])
	for i in 4:
		model.update_crank(fire[i]) # at its own top dead centre, the piston lies on its bank's axis
		var p: Vector3 = model.to_local(model._pistons[i].global_position) - centre
		angles[i] = rad_to_deg(atan2(p.z, p.y)) # the piston's bank angle from vertical, degrees
	check(absf(angles[0] + 45.0) < 1.0, "wire 1 cylinder on the -45 degree bank (%.1f)" % angles[0])
	check(absf(angles[1] - 45.0) < 1.0, "wire 2 cylinder on the +45 degree bank (%.1f)" % angles[1])
	check(absf(angles[2] + 45.0) < 1.0, "wire 3 cylinder on the -45 degree bank (%.1f)" % angles[2])
	check(absf(angles[3] - 45.0) < 1.0, "wire 4 cylinder on the +45 degree bank (%.1f)" % angles[3])
	var pins := {}
	for x in model._pin_x:
		pins[snappedf(x, 0.0001)] = true
	check(pins.size() == 2, "four cylinders share two crank pins (%d)" % pins.size())
	# each rod's crank end sits on its crank pin: the pin turns with the crank, at its bank angle plus its fire angle
	for c in [0.0, 100.0, 333.0, 600.0]:
		model.update_crank(c)
		for i in 4:
			var wrist: Vector3 = model.to_local(model._pistons[i].global_position)
			var rod_mid: Vector3 = model.to_local(model._rods[i].global_position)
			var pin := 2.0 * rod_mid - wrist - centre # crank end of the rod, relative to the crank centre
			var pin_deg := fposmod(rad_to_deg(atan2(pin.z, pin.y)), 360.0)
			var expected := fposmod(-c + angles[i] + fire[i], 360.0)
			var d := fposmod(pin_deg - expected + 180.0, 360.0) - 180.0
			check(absf(d) <= 1.0, "cylinder %d rod on its crank pin at crank %.0f (pin %.1f, expected %.1f)" % [i + 1, c, pin_deg, expected])
	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
