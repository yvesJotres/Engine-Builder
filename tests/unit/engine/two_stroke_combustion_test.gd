extends SceneTree

# Two-stroke combustion fixes, checked against the two engines that already worked.
# - The burn window must follow engine speed, the way the four-stroke's does.
# - Every fresh charge must start its own combustion phasing, so ca50 stays near the spark.
# Run: godot --headless --path . -s tests/unit/engine/two_stroke_combustion_test.gd (prints PASS or FAIL)

var _fails := 0


func _init() -> void:
	await process_frame

	# 1. burn duration rises with engine speed (it used to be a fixed value)
	var slow := TwoStrokeCylinder.burn_duration_deg(2000.0)
	var fast := TwoStrokeCylinder.burn_duration_deg(12000.0)
	check(fast > slow, "the burn spans more crank degrees at 12000 rpm than at 2000 (%.1f vs %.1f)" % [fast, slow])
	check(TwoStrokeCylinder.burn_duration_deg(0.0) > 0.0, "the burn duration stays positive at rest")

	# 2. ca50 must sit near the spark on the engines that run, not drift around the revolution
	for id in ["kawasaki_zx25r", "honda_cbr150r"]:
		var p: Dictionary = Presets.PRESETS[id]
		var spec := EngineSpec.new()
		for key in p.keys():
			spec.set(key, p[key])
		var sim := EngineSim.new()
		sim.physics_dt = 1.0 / 1200.0
		for i in int(2.0 / sim.physics_dt):
			sim.step(sim.physics_dt, spec, 0.0, true, true, false, false, 1.0)
		var ca50: float = sim.cylinders[0].last_ca50
		check(ca50 >= 0.0 and ca50 <= 60.0, "%s burns near top dead centre (ca50 %.1f degrees)" % [id, ca50])
		check(sim.running, "%s holds a running idle" % id)

	print("RESULT: " + ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(1 if _fails > 0 else 0)


func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1
