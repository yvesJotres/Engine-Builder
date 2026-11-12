extends SceneTree

# A two-stroke leaves an unlit charge into an exhaust port that is still glowing from the last firing, and it bangs - the
# same rule the four-stroke uses. The cylinder declared _port_heat and backfire_j and never wrote either, so a two-stroke
# could never pop; this pins the ignition site and the fact that a cold port does not light it.
# Run: godot --headless --path . --quit-after 3000 -s res://tests/unit/engine/two_stroke_backfire_test.gd

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func _cyl() -> TwoStrokeCylinder:
	var spec := EngineSpec.new()
	for key in Presets.PRESETS["yamaha_rd350"].keys():
		spec.set(key, Presets.PRESETS["yamaha_rd350"][key])
	var c := TwoStrokeCylinder.new()
	c.setup(spec)
	return c


func _cross_port(c: TwoStrokeCylinder, tank: FuelTank) -> void:
	# start 5 crank degrees before the exhaust port opens and step over the opening
	c.start_at(c.exhaust_open - 5.0)
	for i in 2:
		c.advance(5.0, 5.0 / (6.0 * 5000.0), 101325.0, 300.0, -20.0, true, tank, 1.0, true, false, Cylinder.P0, Cylinder.T0)


func _init() -> void:
	var tank := FuelTank.new()
	tank.set_kind("ron95")

	# a hot port, unlit fuel in the cylinder, and the port opens: it catches
	var hot := _cyl()
	hot.start_at(hot.exhaust_open - 5.0)
	hot._port_heat = 1100.0
	hot.fuel_unburnt_kg = 2.0e-5
	var before := hot.backfire_j
	for i in 2:
		hot.advance(5.0, 5.0 / (6.0 * 5000.0), 101325.0, 300.0, -20.0, true, tank, 1.0, true, false, Cylinder.P0, Cylinder.T0)
	var after := hot.backfire_j
	print("hot port 1100 K, 2e-5 kg unlit: %.2f J -> %.2f J" % [before, after])
	check(after > before, "an unlit charge bangs into a hot port (%.2f -> %.2f J)" % [before, after])
	check(hot.fuel_unburnt_kg == 0.0, "the charge is spent, not banked for the next cycle (%.8f kg)" % hot.fuel_unburnt_kg)

	# a cold port does not light it, and the fuel is still dropped
	var cold := _cyl()
	cold.start_at(cold.exhaust_open - 5.0)
	cold._port_heat = 400.0
	cold.fuel_unburnt_kg = 2.0e-5
	for i in 2:
		cold.advance(5.0, 5.0 / (6.0 * 5000.0), 101325.0, 300.0, -20.0, true, tank, 1.0, true, false, Cylinder.P0, Cylinder.T0)
	print("cold port 400 K: %.2f J" % cold.backfire_j)
	check(cold.backfire_j == 0.0, "a cold port does not light it (%.2f J)" % cold.backfire_j)
	check(cold.fuel_unburnt_kg == 0.0, "and the fuel does not carry over (%.8f kg)" % cold.fuel_unburnt_kg)

	# a firing cycle heats the port for the next charge to catch from
	var heat := _cyl()
	heat.start_at(heat.exhaust_open - 5.0)
	heat._port_heat = 300.0
	heat._fired = true
	for i in 2:
		heat.advance(5.0, 5.0 / (6.0 * 5000.0), 101325.0, 300.0, -20.0, true, tank, 1.0, true, false, Cylinder.P0, Cylinder.T0)
	print("port heat after a firing crosses the port: %.0f K" % heat._port_heat)
	check(heat._port_heat > 300.0, "a firing heats the port (%.0f K)" % heat._port_heat)

	print("two_stroke_backfire_test: %s" % ("PASS" if _fails == 0 else "FAIL"))
	quit(0 if _fails == 0 else 1)
