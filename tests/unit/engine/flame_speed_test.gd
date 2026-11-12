extends SceneTree

# Laminar flame speed, Metghalchi and Keck (1982), Combustion and Flame 48, 191.
#
# docs/physics-validation.md section 9 listed this as "not used" - the four-stroke burnt with a Wiebe curve and no
# flame-speed model at all. The model now exists (Cylinder.flame_speed_m_s) and this pins it to the published fit,
# evaluated by hand here from the paper's own coefficients, so a wrong exponent or a misread constant fails.
#
#   S_u = S_u0 * (T/T0)^alpha * (p/p0)^beta * (1 - 2.1 f)
#   alpha = 2.18 - 0.8 (phi - 1),  beta = -0.16 + 0.22 (phi - 1),  S_u0 = B_m + B_2 (phi - phi_m)^2
#   isooctane: B_m = 26.32 cm/s, B_2 = -84.72 cm/s, phi_m = 1.13, T0 = 298 K, p0 = 1 atm
#   f = diluent mass fraction (burnt products in the charge), not the residual fraction of the trapped charge
#
# Tag [hand]: a hand evaluation of the cited fit. It checks the implementation, not that Metghalchi-Keck is the right
# model for this engine, and it cannot check the printed digits of B_m/B_2 - the paper text was read, the table was
# transcribed from it (docs/engine_physics/14_what_is_still_unverified.md flags that transcription).
#
# Run: godot --headless --path . -s res://tests/unit/engine/flame_speed_test.gd   (exit 1 on failure)

const T0 := 298.0
const P0 := 101325.0
const PHI_M := 1.13
const B_M := 0.2632 # m/s
const B_2 := -0.8472 # m/s

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


static func near(a: float, b: float, tol: float) -> bool:
	return absf(a - b) <= tol * maxf(1.0, absf(b))


# The published fit, written out here rather than called from the engine.
static func hand(t: float, p: float, phi: float, diluent: float) -> float:
	var su0 := B_M + B_2 * pow(phi - PHI_M, 2.0)
	var alpha := 2.18 - 0.8 * (phi - 1.0)
	var beta := -0.16 + 0.22 * (phi - 1.0)
	return su0 * pow(t / T0, alpha) * pow(p / P0, beta) * (1.0 - 2.1 * diluent)


func _init() -> void:
	# ---- 1. the reference point: at phi_m, T0 and 1 atm the fit must return B_m itself ----
	var ref := Cylinder.flame_speed_m_s(T0, P0, PHI_M, 0.0)
	check(near(ref, B_M, 1.0e-12), "at the reference point S_u is B_m (%.6f vs %.6f m/s)" % [ref, B_M])

	# ---- 2. a loaded, hot point: 600 K and 5 bar at stoichiometric ----
	var hot := Cylinder.flame_speed_m_s(600.0, 5.0e5, 1.0, 0.0)
	var want_hot := hand(600.0, 5.0e5, 1.0, 0.0)
	check(near(hot, want_hot, 1.0e-9), "600 K / 5 bar / phi 1.0: %.4f vs hand calc %.4f m/s" % [hot, want_hot])

	# ---- 3. the diluent factor is linear and worth 21% at f = 0.1 ----
	var diluted := Cylinder.flame_speed_m_s(T0, P0, PHI_M, 0.1)
	check(near(diluted, B_M * 0.79, 1.0e-12),
		"10%% diluent scales the reference speed by 0.79 (%.6f vs %.6f)" % [diluted, B_M * 0.79])
	check(diluted < ref, "diluent slows the flame")

	# ---- 4. the fit's shape: peak at phi_m, rising with temperature, falling with pressure ----
	var lean := Cylinder.flame_speed_m_s(300.0, P0, 1.00, 0.0)
	var peak := Cylinder.flame_speed_m_s(300.0, P0, PHI_M, 0.0)
	var rich := Cylinder.flame_speed_m_s(300.0, P0, 1.40, 0.0)
	check(peak > lean and peak > rich,
		"the speed peaks between phi 1.0 and 1.4 at phi_m (%.3f > %.3f, %.3f)" % [peak, lean, rich])
	var hotter := Cylinder.flame_speed_m_s(500.0, P0, 1.0, 0.0)
	check(hotter > lean, "hotter charge burns faster at the same pressure (%.3f > %.3f)" % [hotter, lean])
	var pressed := Cylinder.flame_speed_m_s(300.0, 3.0 * P0, 1.0, 0.0)
	check(pressed < lean, "pressure slows the flame (%.3f < %.3f m/s)" % [pressed, lean])

	# ---- 5. a plausible band for gasoline at phi 1, 300 K, 1 atm: 0.2-0.35 m/s ----
	check(lean > 0.20 and lean < 0.35, "stoichiometric speed is in the gasoline band (%.3f m/s)" % lean)

	# ---- 6. the diluent clamp keeps the model positive and is documented, not accidental ----
	var heavy := Cylinder.flame_speed_m_s(T0, P0, PHI_M, 0.6)
	var clamped := Cylinder.flame_speed_m_s(T0, P0, PHI_M, Cylinder.FLAME_DILUENT_MAX)
	check(heavy > 0.0, "a heavily diluted charge still burns forwards (%.4f m/s)" % heavy)
	check(near(heavy, clamped, 1.0e-12), "and the diluent is clamped at FLAME_DILUENT_MAX")

	print("S_u: reference %.4f, 600K/5bar %.4f, diluted 10%% %.4f, 300K/1atm/phi1 %.4f m/s" % [ref, hot, diluted, lean])
	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
