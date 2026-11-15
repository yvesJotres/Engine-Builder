extends SceneTree

# Woschni (1967) gas-side heat transfer, gap 3 in docs/physics-validation.md.
#
# The point of this test is that the implementation is checked against the PUBLISHED formula evaluated by hand, not
# against itself: every expected value below is worked out here from the coefficients in
# docs/engine_physics/08_heat_transfer.md, and the code is only asked for its answer.
#
#   h = 3.26 * B^-0.2 * p^0.8 * T^-0.55 * w^0.8      [B m, p kPa, T K, w m/s, h W/(m^2 K)]
#   w = C1 * S_p                                      compression and gas exchange
#   w = C1 * S_p + C2 * (Vd*Tr)/(pr*Vr) * (p - p0)    combustion and expansion only
#   p0 = pr * (Vr/V)^1.4                              motored pressure from the intake-closing state
#
# Coefficients [S] Qasemian and Rezaei 2020, IOP Conf. Ser. 671 012019 (peer-reviewed secondary source; the original
# SAE 670931 text was not reachable, so this checks the implementation, not that Woschni is the right model):
#   3.26 (Pa-unit prefactor 0.0130 * 1000^-0.8), C1 = 2.28 compression/expansion, C1 = 6.18 gas exchange,
#   C2 = 0.00324 m/(s K) combustion/expansion, zero otherwise.
#
# Run: godot --headless --path . -s res://tests/unit/engine/woschni_validation_test.gd   (exit 1 on failure)

const H := 3.26
const C1_COMP := 2.28
const C1_EXCH := 6.18
const C2 := 0.00324
const GAMMA := 1.4

const BORE := 0.062 # m, the cylinder's own bore for this test
const STROKE := 0.0413 # m
const SWEPT := PI * 0.25 * BORE * BORE * STROKE # m^3, worked out here rather than read back from the code
const RPM := 3000.0
const OMEGA := RPM * TAU / 60.0 # rad/s

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


# h from the published correlation, given the gas speed the caller worked out by hand.
static func hand_h(p_kpa: float, t: float, w: float) -> float:
	return H * pow(BORE, -0.2) * pow(p_kpa, 0.8) * pow(t, -0.55) * pow(w, 0.8)


static func sp() -> float:
	# mean piston speed from the crank speed: S_p = stroke * omega / pi  (== 2 * stroke * rpm / 60)
	return STROKE * OMEGA / PI


func near(got: float, want: float, tol: float) -> bool:
	return absf(got - want) <= tol * maxf(1.0, absf(want))


func _init() -> void:
	var cyl := Cylinder.new()
	cyl.setup(BORE * 1000.0, STROKE * 1000.0, 11.5) # setup takes mm
	check(is_equal_approx(cyl.bore, BORE), "bore is %.4f m, wanted %.4f" % [cyl.bore, BORE])
	check(is_equal_approx(cyl.stroke, STROKE), "stroke is %.4f m, wanted %.4f" % [cyl.stroke, STROKE])

	# ---- 1. motored compression: w = C1 * S_p, no pressure-rise term ----
	var p_comp := 1_200_000.0 # Pa
	var t_comp := 700.0 # K
	var w_comp := C1_COMP * sp()
	var want_comp := hand_h(p_comp / 1000.0, t_comp, w_comp)
	var got_comp := cyl.woschni_h(OMEGA, p_comp, t_comp, 4.0e-5, false, false)
	check(near(got_comp, want_comp, 1.0e-6),
		"motored h %.3f vs hand calc %.3f W/(m^2 K)" % [got_comp, want_comp])
	# A motored point at 12 bar / 700 K / 3000 rpm lands in the few-hundred band. Plausibility only, printed.
	check(got_comp > 100.0 and got_comp < 600.0, "motored h is in the plausible band (%.1f)" % got_comp)

	# ---- 2. combustion and expansion: the C2 pressure-rise term speeds the gas up ----
	# Intake-closing state and a fired state near peak pressure. p0 is the motored pressure at that volume.
	var ivc_p := 101325.0
	var ivc_v := 1.11e-4 # m^3
	var ivc_t := 320.0
	cyl._ivc_p = ivc_p
	cyl._ivc_v = ivc_v
	cyl._ivc_t = ivc_t
	var p_fired := 8_000_000.0
	var t_fired := 2600.0
	var v_fired := 2.0e-5
	var p0 := ivc_p * pow(ivc_v / v_fired, GAMMA)
	var w_fired := C1_COMP * sp() + C2 * SWEPT * ivc_t / (ivc_p * ivc_v) * (p_fired - p0)
	var want_fired := hand_h(p_fired / 1000.0, t_fired, w_fired)
	var got_fired := cyl.woschni_h(OMEGA, p_fired, t_fired, v_fired, true, false)
	check(near(got_fired, want_fired, 1.0e-6),
		"fired h %.1f vs hand calc %.1f W/(m^2 K)" % [got_fired, want_fired])
	# and the term is what did it: the same state without combustion must come out lower
	var got_fired_noburn := cyl.woschni_h(OMEGA, p_fired, t_fired, v_fired, false, false)
	check(got_fired > got_fired_noburn,
		"combustion raises h above the motored value at the same p and T (%.1f vs %.1f)" % [got_fired, got_fired_noburn])
	print("fired: p0 %.1f kPa, C2 velocity term %.1f m/s, w %.1f m/s (S_p %.2f)" % [
		p0 / 1000.0, w_fired - C1_COMP * sp(), w_fired, sp()])

	# ---- 3. gas exchange: C1 = 6.18, and C2 stays out of it (it is combustion/expansion only) ----
	var p_exch := 101325.0
	var t_exch := 420.0
	var w_exch := C1_EXCH * sp()
	var want_exch := hand_h(p_exch / 1000.0, t_exch, w_exch)
	var got_exch := cyl.woschni_h(OMEGA, p_exch, t_exch, 1.2e-4, false, true)
	check(near(got_exch, want_exch, 1.0e-6),
		"gas-exchange h %.1f vs hand calc %.1f W/(m^2 K)" % [got_exch, want_exch])
	# burning is ignored during gas exchange: no C2 term, same answer as above
	var got_exch_burning := cyl.woschni_h(OMEGA, p_exch, t_exch, 1.2e-4, true, true)
	check(near(got_exch_burning, got_exch, 1.0e-9),
		"gas exchange ignores the combustion term (%.3f vs %.3f)" % [got_exch_burning, got_exch])
	check(got_exch > cyl.woschni_h(OMEGA, p_exch, t_exch, 1.2e-4, false, false),
		"gas exchange passes more gas over the walls than compression at the same state")

	# ---- 3b. the constants themselves are the published triple, not tuned per bike ----
	# Qasemian and Rezaei 2020 (the paper is in docs/papers/): C1 and C2 are 6.18 and 0.0 for gas exchange, 2.28 and 0.0
	# for compression, and 2.28 and 0.00324 for combustion and expansion. Retuning these to bring a dyno curve down is the
	# fudge factor GEMINI.md section 5 forbids, so this is the line that makes that visible.
	check(is_equal_approx(Cylinder.WOSCHNI_C1, C1_COMP), "C1 compression/expansion is the published 2.28 (%.5f)" % Cylinder.WOSCHNI_C1)
	check(is_equal_approx(Cylinder.WOSCHNI_C1_GAS, C1_EXCH), "C1 gas exchange is the published 6.18 (%.5f)" % Cylinder.WOSCHNI_C1_GAS)
	check(is_equal_approx(Cylinder.WOSCHNI_C2, C2), "C2 is the published 0.00324 m/(s K) (%.6f)" % Cylinder.WOSCHNI_C2)
	check(is_equal_approx(Cylinder.WOSCHNI_H, 3.26), "the prefactor is the published 3.26 (%.4f)" % Cylinder.WOSCHNI_H)

	# ---- 4. the exponents: doubling the pressure must scale h by 2^0.8 ----
	var half := cyl.woschni_h(OMEGA, p_comp * 0.5, t_comp, 4.0e-5, false, false)
	check(near(got_comp / half, pow(2.0, 0.8), 1.0e-9),
		"p^0.8 exponent holds (%.4f, wanted %.4f)" % [got_comp / half, pow(2.0, 0.8)])

	print("motored %.1f, fired %.1f, gas exchange %.1f W/(m^2 K) at %.0f rpm" % [
		got_comp, got_fired, got_exch, RPM])
	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
