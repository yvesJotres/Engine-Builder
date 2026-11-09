extends SceneTree

# The fuel and air paths. An injected engine has a nozzle on every cylinder and a fuel rail joining them. The two-stroke carburettor
# has a jet per cylinder and no rail. A quick throttle opening richens the mixture, and the richness fades back to the steady
# mixture. Exits 1 on any failure. Run: godot --headless --path . -s res://tests/unit/engine/induction_test.gd

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


func _init() -> void:
	await process_frame
	# injection: a nozzle on every cylinder
	var zx := _spec("kawasaki_zx25r")
	check(zx.induction == "injection", "the ZX-25R is injected, got '%s'" % zx.induction)
	var zx_model := EngineModel.new()
	root.add_child(zx_model)
	zx_model.build(zx)
	check(zx_model.injector_positions().size() == zx.cylinders, "one nozzle per cylinder, got %d for %d" % [zx_model.injector_positions().size(), zx.cylinders])
	check(zx_model._plates.size() == zx.cylinders, "one throttle body per cylinder, got %d" % zx_model._plates.size())
	zx_model.free()

	# carburettor: a jet per cylinder, a throttle plate per cylinder, and no fuel rail
	var rd := _spec("yamaha_rd350")
	check(rd.induction == "carburettor", "the RD350 has a carburettor, got '%s'" % rd.induction)
	var rd_model := EngineModel.new()
	root.add_child(rd_model)
	rd_model.build(rd)
	check(rd_model.injector_positions().size() == rd.cylinders, "one carburettor jet per cylinder, got %d" % rd_model.injector_positions().size())
	check(rd_model._plates.size() == rd.cylinders, "one throttle plate per carburettor, got %d" % rd_model._plates.size())
	rd_model.free()

	# transient fuel: a snap of the throttle richens the mixture, and the richness goes away once it has settled
	var sim := EngineSim.new()
	sim.physics_dt = 1.0 / 2400.0
	sim.fuel.set_kind(zx.fuel)
	for i in 2 * 60:
		for j in 40:
			sim.step(sim.physics_dt, zx, 0.0, true, true, false, false, 1.0)
	for j in 40:
		sim.step(sim.physics_dt, zx, 0.0, true, false, false, false, 1.0)
	var rich := sim._transient_lambda_mult(0.0, sim.physics_dt)
	check(absf(rich - 1.0) < 0.001, "no enrichment at a steady throttle, got %.3f" % rich)
	var snap := sim._transient_lambda_mult(1.0, sim.physics_dt)
	check(snap < 0.95, "a snap open richens the mixture, multiplier %.3f" % snap)
	check(snap > 1.0 - sim.ACCEL_ENRICH_MAX - 0.001, "the enrichment is capped, multiplier %.3f" % snap)
	for j in int(3.0 * 2400.0):
		sim._transient_lambda_mult(1.0, sim.physics_dt)
	var settled := sim._transient_lambda_mult(1.0, sim.physics_dt)
	check(absf(settled - 1.0) < 0.01, "the richness fades after three seconds, multiplier %.3f" % settled)

	print("induction_test: %s" % ("PASSED" if _fails == 0 else "FAILED"))
	quit(0 if _fails == 0 else 1)
