extends SceneTree

# Combustion drawn from the simulation's own burn state: the charge lights at the plug, a spark flashes there, and the
# flame front fills the chamber as burn_energy_left falls, its colour following the gas temperature. This drives the
# view with crafted cylinders (a burn fraction of 30% and 90%, then a complete burn) so the size, the ignition moment
# and the fade are checked without depending on an engine run, and then runs the real engine for a second to prove
# something actually lights up in the game.
# Run: godot --headless --path . -s res://tests/unit/engine/combustion_view_test.gd   (prints PASS or FAIL)

# the view's own size limits, so the test fails if they are ever set wrong rather than silently agreeing with them
const FLAME_MIN := 0.18
const FLAME_MAX := 0.49

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func _init() -> void:
	await process_frame

	# ---- the view, built for a four-cylinder engine and driven by hand ----
	var spec: EngineSpec = DynoRunner.spec_for("kawasaki_zx25r_se")
	var model := EngineModel.new()
	root.add_child(model)
	model.build(spec)
	model.update_crank(0.0)
	var bore: float = spec.bore_mm * Units.MM_TO_SCENE
	print("flames built: %d for %d cylinders" % [model.flame_count(), spec.cylinders])
	check(model.flame_count() == spec.cylinders, "one flame per cylinder (%d)" % model.flame_count())
	check(model.chamber_plug(0).distance_to(model.flame_position(0)) < 0.06,
		"the flame sits at the plug (%.3f units away)" % model.chamber_plug(0).distance_to(model.flame_position(0)))

	var cyls: Array = []
	for i in spec.cylinders:
		var c := Cylinder.new()
		cyls.append(c)
	for c in cyls:
		c.burn_energy = 1000.0
		c.burn_energy_left = 1000.0
		c.temp = 1800.0
	model.update_combustion(cyls, 0.016)
	check(not model.flame_visible(0), "an unlit charge draws no flame")

	# 30% burned: lit, and the spark fires on the transition from unlit
	cyls[0].burn_energy_left = 700.0
	cyls[0].temp = 2000.0
	model.update_combustion(cyls, 0.016)
	var r30: float = model.flame_radius(0)
	print("30%% burned, 2000 K: flame %.3f units, spark %s, plug %.3f" % [r30, model.spark_visible(0), model.chamber_plug(0).y])
	check(model.flame_visible(0), "a burning charge draws a flame")
	check(model.spark_visible(0), "ignition shows the spark")
	check(r30 > bore * FLAME_MIN and r30 < bore * FLAME_MAX, "the 30%% flame is a kernel, not the whole bore (%.3f of %.3f)" % [r30, bore])
	check(model.combustion_light_energy(0) > 0.0, "the burn lights the chamber, so it shows through the covers too")

	# 90% burned: the front has reached the wall
	cyls[0].burn_energy_left = 100.0
	cyls[0].temp = 2500.0
	model.update_combustion(cyls, 0.016)
	var r90: float = model.flame_radius(0)
	print("90%% burned, 2500 K: flame %.3f units" % r90)
	check(r90 > r30, "the flame front grows with the burn (%.3f -> %.3f)" % [r30, r90])
	check(absf(model.flame_position(0).y - model.chamber_plug(0).y) < 0.12, "it stays at the chamber roof as it grows")

	# ---- containment: the flame is in the chamber, not in the head and not in the crankcase ----
	model.update_crank(0.0) # cylinder 0 at firing TDC: the tightest the chamber ever is
	cyls[0].burn_energy_left = 400.0 # 60% burned
	cyls[0].temp = 2300.0
	model.update_combustion(cyls, 0.016)
	var ch: Dictionary = model.chamber_local(0)
	var fl: Dictionary = model.flame_local(0)
	print("TDC chamber %.3f..%.3f, flame %.3f..%.3f, radius %.3f of %.3f"
		% [ch.crown, ch.roof, fl.bottom, fl.top, fl.radius, float(ch.bore) * 0.5])
	check(fl.bottom >= float(ch.crown) - 0.001, "the flame does not reach below the piston crown")
	check(fl.top <= float(ch.roof) + 0.001, "the flame does not reach into the head")
	check(fl.radius <= float(ch.bore) * 0.5, "the flame stays inside the bore (%.3f of %.3f)" % [fl.radius, float(ch.bore) * 0.5])
	model.update_crank(90.0) # the piston on its way down: the chamber grows
	model.update_combustion(cyls, 0.016)
	var ch2: Dictionary = model.chamber_local(0)
	var fl2: Dictionary = model.flame_local(0)
	print("90 deg chamber %.3f..%.3f, flame %.3f..%.3f" % [ch2.crown, ch2.roof, fl2.bottom, fl2.top])
	check(fl2.bottom >= float(ch2.crown) - 0.001 and fl2.top <= float(ch2.roof) + 0.001,
		"contained mid-stroke too (%.3f..%.3f in %.3f..%.3f)" % [fl2.bottom, fl2.top, ch2.crown, ch2.roof])
	check(float(ch2.crown) < float(ch.crown), "the crown drops as the crank turns (%.3f -> %.3f)" % [ch.crown, ch2.crown])

	# the spark is a flash, not a lamp
	for i in 5:
		model.update_combustion(cyls, 0.02)
	check(not model.spark_visible(0), "the spark goes out within a tenth of a second")

	# a complete burn: the glow is held for a moment, then gone (a flame does not wink out on a frame boundary)
	cyls[0].burn_energy_left = 0.0
	model.update_combustion(cyls, 0.016)
	for i in 4:
		model.update_combustion(cyls, 0.02)
	check(not model.flame_visible(0), "the glow is gone once the burn is over")

	# ---- the real engine: something must actually light up ----
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 6:
		await process_frame
	main._panel_starter = true
	var flames := 0
	var sparks := 0
	for f in 300:
		await process_frame
		for i in main._model.flame_count():
			if main._model.flame_visible(i):
				flames += 1
			if main._model.spark_visible(i):
				sparks += 1
	print("running engine: %d flame frames, %d spark frames over 300" % [flames, sparks])
	check(flames > 0, "the running engine draws combustion")
	check(sparks > 0, "the running engine fires the spark")

	if _fails == 0:
		print("combustion_view_test: PASS (flame follows the burn, spark fires at ignition)")
	quit(0 if _fails == 0 else 1)
