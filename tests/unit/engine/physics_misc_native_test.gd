extends SceneTree

# PhysicsMiscNative (gdextension/src/physics_misc_native.cpp): Stribeck friction and isentropic nozzle flow.
# There is no GDScript reference, so this checks values worked out by hand from the formulas.
# Run: godot --headless --path . -s tests/unit/engine/physics_misc_native_test.gd
const REL_TOL := 1.0e-9

var failures := 0


func _init() -> void:
	await process_frame
	if not ClassDB.class_exists("PhysicsMiscNative"):
		print("SKIP: PhysicsMiscNative is not loaded, nothing to compare")
		quit(2)
		return
	_friction()
	_flow()
	print("physics_misc_native_test: %s" % ("PASSED" if failures == 0 else "FAILED (%d problems)" % failures))
	quit(0 if failures == 0 else 1)


func _expect(label: String, got: float, want: float, tol: float = REL_TOL) -> void:
	if absf(got - want) > tol * maxf(1.0, absf(want)):
		failures += 1
		print("FAIL %s: got %.12g want %.12g" % [label, got, want])


# Stribeck friction (ATG calculateFrictionForce), v = |v_s|:
#   F_coul = mu * N          v_st = vb * sqrt(2)      v_coul = vb / 10
#   F_0 = sqrt(2) * e * (F_brk - F_coul)
#   F = F_0 * x * exp(-x^2) + F_coul * tanh(v / v_coul) + c * v      with x = v / v_st
func _stribeck(v_s: float, n: float, mu: float, f_brk: float, vb: float, c: float) -> float:
	var v := absf(v_s)
	var f_coul := mu * n
	var x := v / (vb * sqrt(2.0))
	return sqrt(2.0) * exp(1.0) * (f_brk - f_coul) * x * exp(-x * x) + f_coul * tanh(v / (vb / 10.0)) + c * v


func _friction() -> void:
	var d := {} # defaults: mu 0.06, F_brk 50 N, vb 0.1 m/s, c 20 N/(m/s)
	# Zero speed: every term is zero.
	_expect("friction v=0", PhysicsMiscNative.calculate_friction(0.0, 1000.0, d), 0.0)
	# At v = v_st the Stribeck term is F_0 * exp(-1): x = 1 so F = sqrt(2) * e * (F_brk - F_coul) / e = sqrt(2) * (F_brk - F_coul).
	# v_st = 0.1 * sqrt(2). N = 500: F_coul = 30, F_0 term = sqrt(2) * 20 = 28.2842712475,
	# Coulomb term = 30 * tanh(0.1414213562 / 0.01) = 30 * tanh(14.14) = 30, viscous = 20 * 0.1414213562 = 2.828427125.
	# Total = 28.2842712475 + 30 + 2.828427125 = 61.1126983722.
	var v_st := 0.1 * sqrt(2.0)
	_expect("friction at v_st", PhysicsMiscNative.calculate_friction(v_st, 500.0, d), 61.11269837217687, 1e-9)
	_expect("friction at v_st matches formula", PhysicsMiscNative.calculate_friction(v_st, 500.0, d),
		_stribeck(v_st, 500.0, 0.06, 50.0, 0.1, 20.0))
	# Sign of the speed does not matter (the magnitude is returned, the caller applies direction).
	_expect("friction sign", PhysicsMiscNative.calculate_friction(-v_st, 500.0, d), PhysicsMiscNative.calculate_friction(v_st, 500.0, d))
	# A spread of speeds and loads against the formula.
	for v in [0.001, 0.01, 0.05, 0.3, 1.0, 5.0, 25.0]:
		for n in [0.0, 100.0, 2500.0]:
			_expect("friction v=%s N=%s" % [v, n], PhysicsMiscNative.calculate_friction(v, n, d),
				_stribeck(v, n, 0.06, 50.0, 0.1, 20.0))
	# Custom parameters.
	var p := {"friction_coeff": 0.1, "breakaway_friction": 80.0, "breakaway_friction_velocity": 0.2, "viscous_friction_coefficient": 5.0}
	for v in [0.02, 0.2, 2.0]:
		_expect("friction custom v=%s" % v, PhysicsMiscNative.calculate_friction(v, 300.0, p), _stribeck(v, 300.0, 0.1, 80.0, 0.2, 5.0))
	# Zero breakaway velocity guard: falls back to Coulomb plus viscous, mu * N + c * |v|, with no NaN or inf.
	# mu 0.06, N 500, c 20, v = -2: 30 + 40 = 70.
	var z := {"breakaway_friction_velocity": 0.0}
	_expect("friction zero-vb guard", PhysicsMiscNative.calculate_friction(-2.0, 500.0, z), 70.0)
	_expect("friction zero-vb at rest", PhysicsMiscNative.calculate_friction(0.0, 500.0, z), 30.0)
	var neg := {"breakaway_friction_velocity": -1.0}
	_expect("friction negative-vb guard", PhysicsMiscNative.calculate_friction(2.0, 500.0, neg), 70.0)


# Isentropic nozzle flow (ATG GasSystem::flowRate), r = p_down / p_up, g = gamma:
#   choked limit = (2 / (g + 1))^(g / (g - 1))        for g = 1.4 this is 0.528281787...
#   choked (r <= limit):  k * p_up * sqrt(g) * (2 / (g + 1))^((g + 1) / (2 (g - 1))) / sqrt(R * T)
#   subsonic (r > limit): k * p_up * sqrt( (2 g / (g - 1)) * s * (s - r) / (R * T) ),  s = r^(1 / g)
func _flow() -> void:
	var g := 1.4
	var gas_r := 287.0
	var t := 300.0
	var p := 200000.0
	# Choked: p_down / p_up = 0.25 < 0.5283. Factor sqrt(1.4) * (2 / 2.4)^3 = 1.1832159566 * 0.5787037037 = 0.6847314564
	# flow = 200000 * 0.6847314 / sqrt(287 * 300) = 200000 * 0.6847314 / 293.4280150 = 466.7216...
	var choked_factor := sqrt(g) * pow(2.0 / (g + 1.0), (g + 1.0) / (2.0 * (g - 1.0)))
	var want_choked := p * choked_factor / sqrt(gas_r * t)
	_expect("choked flow", PhysicsMiscNative.flow_rate(p, t, 0.25 * p, 1.0, g, gas_r), want_choked)
	_expect("choked factor literal", choked_factor, 0.6847314564, 1e-9)
	# Choked flow does not depend on the downstream pressure.
	_expect("choked independent of p_down", PhysicsMiscNative.flow_rate(p, t, 0.05 * p, 1.0, g, gas_r), want_choked)
	# k_flow scales the result linearly.
	_expect("k_flow scales", PhysicsMiscNative.flow_rate(p, t, 0.25 * p, 2.5e-4, g, gas_r), 2.5e-4 * want_choked)
	# At exactly the choked limit the choked branch is used (r <= limit), and the subsonic formula gives the same number there.
	var limit := pow(2.0 / (g + 1.0), g / (g - 1.0))
	_expect("choked limit value", limit, 0.5282817877, 1e-9)
	_expect("at the limit", PhysicsMiscNative.flow_rate(p, t, limit * p, 1.0, g, gas_r), want_choked, 1e-9)
	# Subsonic: r = 0.8, s = 0.8^(1/1.4) = 0.852...; evaluate the formula.
	for r in [0.6, 0.8, 0.95, 0.999]:
		var s := pow(r, 1.0 / g)
		var want: float = p * sqrt((2.0 * g / (g - 1.0)) * s * (s - r) / (gas_r * t))
		_expect("subsonic r=%s" % r, PhysicsMiscNative.flow_rate(p, t, r * p, 1.0, g, gas_r), want)
	# Equal pressures: no flow. Downstream above upstream: the negative term is clamped, so the flow is 0.
	_expect("equal pressures", PhysicsMiscNative.flow_rate(p, t, p, 1.0, g, gas_r), 0.0)
	_expect("reversed pressures", PhysicsMiscNative.flow_rate(p, t, 1.5 * p, 1.0, g, gas_r), 0.0)
	# k_flow of zero returns 0 straight away.
	_expect("zero k_flow", PhysicsMiscNative.flow_rate(p, t, 0.25 * p, 0.0, g, gas_r), 0.0)
	# A different gamma (burnt gas, 1.3): the limit moves to (2 / 2.3)^(1.3 / 0.3) = 0.5457...
	var g2 := 1.3
	var f2 := sqrt(g2) * pow(2.0 / (g2 + 1.0), (g2 + 1.0) / (2.0 * (g2 - 1.0)))
	_expect("gamma 1.3 choked", PhysicsMiscNative.flow_rate(p, t, 0.1 * p, 1.0, g2, gas_r), p * f2 / sqrt(gas_r * t))
