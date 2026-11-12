extends SceneTree

# Orifice mass flow, gap 5 in docs/physics-validation.md.
#
# Cylinder.mass_flow() is the Heywood App C compressible-orifice relation, and this checks it against the closed form
# worked out here, with the constants taken from the published equations rather than from the code:
#
#   choked  (p_down/p_up <= (2/(gamma+1))^(gamma/(gamma-1)) = 0.5283)
#     mdot = Cd * A * p_up / sqrt(R*T_up) * sqrt(gamma * (2/(gamma+1))^((gamma+1)/(gamma-1)))
#   subsonic
#     mdot = Cd * A * p_up / sqrt(R*T_up) * sqrt(2*gamma/(gamma-1) * (pr^(2/gamma) - pr^((gamma+1)/gamma)))
#
# and pins the properties that make it a usable flow model: continuity across the critical ratio, the choked plateau,
# sign symmetry, linearity in area and in p_up, and the approach to zero as the pressures equalise.
#
# Cd here is the reference Cylinder.CD_VALVE = 0.7, which mass_flow() applies itself.
#
# References: Heywood, Internal Combustion Engine Fundamentals, App. C (compressible flow through a restriction);
# docs/engine_physics/13_sources.md. Tags: [closed] for the choked/subsonic forms and the critical ratio.
#
# Run: godot --headless --path . -s res://tests/unit/engine/orifice_flow_test.gd   (exit 1 on failure)

const CD := 0.7 # the reference coefficient mass_flow applies, per its own constant
const RR := 287.0 # J/(kg K), the gas constant mass_flow uses
const GAMMA := 1.4

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


static func near(got: float, want: float, tol: float) -> bool:
	return absf(got - want) <= tol * maxf(1.0, absf(want))


# The critical pressure ratio, from the closed form.
static func critical_ratio() -> float:
	return pow(2.0 / (GAMMA + 1.0), GAMMA / (GAMMA - 1.0))


static func hand_choked(area: float, p_up: float, t_up: float) -> float:
	var k := CD * area * p_up / sqrt(RR * t_up)
	return k * sqrt(GAMMA * pow(2.0 / (GAMMA + 1.0), (GAMMA + 1.0) / (GAMMA - 1.0)))


static func hand_subsonic(area: float, p_up: float, t_up: float, pr: float) -> float:
	var k := CD * area * p_up / sqrt(RR * t_up)
	return k * sqrt(2.0 * GAMMA / (GAMMA - 1.0) * (pow(pr, 2.0 / GAMMA) - pow(pr, (GAMMA + 1.0) / GAMMA)))


func _init() -> void:
	var area := 1.0e-4 # m², a valve-sized hole
	var p_up := 200_000.0 # Pa
	var t_up := 400.0 # K

	# ---- the critical ratio itself ----
	var crit := critical_ratio()
	check(near(crit, 0.5283, 1.0e-4), "critical pressure ratio %.4f, the closed form gives 0.5283" % crit)

	# ---- choked: below the critical ratio the flow is fixed by the upstream state only ----
	var choked := Cylinder.mass_flow(area, p_up, t_up, p_up * 0.25, 400.0)
	var want_choked := hand_choked(area, p_up, t_up)
	check(near(choked, want_choked, 1.0e-9),
		"choked flow %.6f kg/s vs hand calc %.6f" % [choked, want_choked])
	# and it does not care what the downstream pressure is, as long as it is under the critical ratio
	var choked_lower := Cylinder.mass_flow(area, p_up, t_up, p_up * 0.10, 400.0)
	check(near(choked_lower, choked, 1.0e-12),
		"choked flow is flat in downstream pressure (%.9f vs %.9f)" % [choked_lower, choked])

	# ---- subsonic: above the critical ratio the downstream pressure matters ----
	var pr := 0.70
	var subsonic := Cylinder.mass_flow(area, p_up, t_up, p_up * pr, 400.0)
	var want_subsonic := hand_subsonic(area, p_up, t_up, pr)
	check(near(subsonic, want_subsonic, 1.0e-9),
		"subsonic flow at pr %.2f: %.6f kg/s vs hand calc %.6f" % [pr, subsonic, want_subsonic])

	# ---- continuity across the critical ratio: the two branches must meet ----
	var just_under := Cylinder.mass_flow(area, p_up, t_up, p_up * crit * (1.0 - 1.0e-9), 400.0)
	var just_over := Cylinder.mass_flow(area, p_up, t_up, p_up * crit * (1.0 + 1.0e-9), 400.0)
	check(near(just_under, just_over, 1.0e-8),
		"the choked and subsonic branches meet at the critical ratio (%.9f vs %.9f)" % [just_under, just_over])

	# ---- monotonic in the pressure ratio, right up to the plateau ----
	var f90 := Cylinder.mass_flow(area, p_up, t_up, p_up * 0.90, 400.0)
	var f70 := subsonic
	var f50 := Cylinder.mass_flow(area, p_up, t_up, p_up * 0.50, 400.0)
	var f30 := Cylinder.mass_flow(area, p_up, t_up, p_up * 0.30, 400.0)
	check(f90 < f70 and f70 < f50, "flow rises as the downstream pressure falls (%.6f < %.6f < %.6f)" % [f90, f70, f50])
	check(near(f50, f30, 1.0e-12), "and stops rising once it is choked (%.9f vs %.9f)" % [f50, f30])

	# ---- equal pressures: nothing flows ----
	var equal := Cylinder.mass_flow(area, p_up, t_up, p_up * 0.9999, 400.0)
	check(near(equal, hand_subsonic(area, p_up, t_up, 0.9999), 1.0e-9),
		"near-balanced flow still matches the subsonic form (%.8f kg/s)" % equal)
	check(absf(equal) < 0.05 * choked, "and it is a small fraction of the choked flow (%.8f vs %.6f)" % [equal, choked])
	var closer := Cylinder.mass_flow(area, p_up, t_up, p_up * 0.999999, 400.0)
	check(absf(closer) < absf(equal), "and it keeps falling as the pressures meet (%.10f vs %.10f)" % [closer, equal])

	# ---- reversed flow is the same magnitude, opposite sign ----
	var forward := Cylinder.mass_flow(area, p_up, t_up, p_up * 0.5, 500.0)
	var reverse := Cylinder.mass_flow(area, p_up * 0.5, 500.0, p_up, t_up)
	check(reverse < 0.0 and near(-reverse, forward, 1.0e-12),
		"reversing the orifice flips the sign and keeps the magnitude (%.9f vs -%.9f)" % [forward, reverse])

	# ---- linear in area and in upstream pressure, at fixed temperature and ratio ----
	var double_area := Cylinder.mass_flow(area * 2.0, p_up, t_up, p_up * 0.5, 400.0)
	check(near(double_area, 2.0 * forward, 1.0e-12), "flow is linear in area")
	var double_p := Cylinder.mass_flow(area, p_up * 2.0, t_up, p_up * 1.0, 400.0)
	check(near(double_p, 2.0 * forward, 1.0e-12), "flow is linear in upstream pressure at fixed ratio")

	# ---- a closed valve passes nothing ----
	check(Cylinder.mass_flow(0.0, p_up, t_up, 0.0, 400.0) == 0.0, "zero area passes no flow")

	print("choked %.6f kg/s, subsonic(pr 0.70) %.6f, plateau from pr %.4f" % [choked, subsonic, crit])
	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
