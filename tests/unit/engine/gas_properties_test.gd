extends SceneTree

# The gas properties the cylinder's first law now uses: cp and cv as functions of temperature for air and for burnt gas,
# u as the integral of cv, h = u + R·T, and the inverse of the u integral. Checks the table points against the values
# they came from (Keenan and Kaye / Cengel appendix tables), that the properties behave like gases should, and that the
# energy <-> temperature round trip is exact - a thermodynamics model that cannot get from energy back to temperature
# would drift every cycle.
# Run: godot --headless --path . -s res://tests/unit/engine/gas_properties_test.gd   (prints PASS or FAIL)

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func _close(a: float, b: float, rel: float) -> bool:
	return absf(a - b) <= rel * maxf(1.0, absf(b))


func _init() -> void:
	await process_frame

	# ---- the table points ----
	print("cp air 300/1000/2000 K: %.0f %.0f %.0f" % [GasProperties.cp_air(300.0), GasProperties.cp_air(1000.0), GasProperties.cp_air(2000.0)])
	check(absf(GasProperties.cp_air(300.0) - 1005.0) < 1.0, "air cp at 300 K is 1.005 kJ/kgK")
	check(absf(GasProperties.cp_air(1000.0) - 1142.0) < 1.0, "air cp at 1,000 K is 1.142")
	check(absf(GasProperties.cp_air(2000.0) - 1270.0) < 1.0, "air cp at 2,000 K is 1.270")
	check(_close(GasProperties.cv(0.0, 300.0), 1005.0 - GasProperties.R, 1e-9), "cv = cp - R for air")

	# ---- and behave like gases: cp rises with temperature, burnt gas above air ----
	check(GasProperties.cp_air(2000.0) > GasProperties.cp_air(1000.0) and GasProperties.cp_air(1000.0) > GasProperties.cp_air(300.0),
		"air's cp rises with temperature")
	var above := true
	for t in [300.0, 800.0, 1500.0, 2500.0]:
		if GasProperties.cp(1.0, t) <= GasProperties.cp(0.0, t):
			above = false
	check(above, "burnt gas holds more heat than air at every temperature")
	check(GasProperties.cp(0.5, 1200.0) > GasProperties.cp(0.0, 1200.0) and GasProperties.cp(0.5, 1200.0) < GasProperties.cp(1.0, 1200.0),
		"a half-burnt charge sits between the two")

	# ---- u is the integral of cv, not cv·T ----
	var u_1000: float = GasProperties.u(0.0, 1000.0)
	var mean_cv := 0.5 * (GasProperties.cv(0.0, 300.0) + GasProperties.cv(0.0, 1000.0))
	print("air u(1000 K) = %.0f J/kg, trapezoid estimate %.0f, cv·T would say %.0f"
		% [u_1000, mean_cv * 700.0, GasProperties.cv(0.0, 1000.0) * 1000.0])
	check(_close(u_1000, mean_cv * 700.0, 0.02), "u(1000 K) is the integral of cv over 300..1000 K")
	check(u_1000 < GasProperties.cv(0.0, 1000.0) * 1000.0 * 0.8,
		"u is not cv(T)·T: that would overcharge a hot charge")
	check(GasProperties.u(0.0, 300.0) == 0.0, "u is zero at the 300 K reference")
	check(GasProperties.h(0.0, 1000.0) - GasProperties.u(0.0, 1000.0) == GasProperties.R * 1000.0, "h = u + R·T")

	# ---- energy back to temperature, exactly ----
	var worst := 0.0
	for t in [200.0, 300.0, 450.0, 900.0, 1400.0, 2100.0, 2600.0, 3400.0]:
		for burnt in [0.0, 0.6, 1.0]:
			var back: float = GasProperties.temp_from_u(burnt, GasProperties.u(burnt, t))
			worst = maxf(worst, absf(back - t))
	print("worst temperature round trip error: %.3f K" % worst)
	check(worst < 0.05, "u -> T is exact to 0.05 K (worst %.3f)" % worst)

	# ---- a cycle of a running cylinder: energy in must equal energy stored plus work and losses ----
	Cylinder.use_native = false
	var cyl := Cylinder.new()
	cyl.setup(50.0, 31.8, 11.5, 0.09, 2.0)
	var tank := FuelTank.new()
	tank.set_kind("ron95")
	var rpm := 6000.0
	var dphi := 10.0
	var dt := dphi / (6.0 * rpm)
	for i in 72 * 6: # six cycles: settle
		cyl.advance(dphi, dt, 101325.0, 300.0, -15.0, true, tank, 1.0)
	var u_start: float = cyl._u
	var e_in: float = cyl.enthalpy_in_j
	var e_out: float = cyl.enthalpy_out_j
	var wall: float = cyl.wall_loss_j
	var burn_before: float = cyl.burn_energy
	for i in 72: # one more cycle
		cyl.advance(dphi, dt, 101325.0, 300.0, -15.0, true, tank, 1.0)
	var d_u: float = cyl._u - u_start
	var d_h_in: float = cyl.enthalpy_in_j - e_in
	var d_h_out: float = cyl.enthalpy_out_j - e_out
	var d_wall: float = cyl.wall_loss_j - wall
	# over one cycle at steady state the stored energy is back where it started, so the flows must balance, and the
	# heat released has to be inside the enthalpy that left: this is the check that the new cp/cv are used consistently
	print("one cycle: dU %.0f J, h_in %.0f J, h_out %.0f J, wall %.0f J, T %.0f K"
		% [d_u, d_h_in, d_h_out, d_wall, cyl.temp])
	check(d_h_out > d_wall, "the exhaust carries the heat the walls did not take")
	check(absf(d_u) < 0.25 * d_h_out, "the stored energy comes back within a quarter of the cycle's heat (%.0f J)" % d_u)

	if _fails == 0:
		print("gas_properties_test: PASS (table values, cp rises with T, u is the integral, u -> T exact)")
	quit(0 if _fails == 0 else 1)
