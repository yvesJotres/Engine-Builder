extends SceneTree

# Valve curtain area, Heywood's form: the open area at a poppet valve is the cylinder through the seat,
#   A = pi * d_valve * lift          (per valve)
# and it stops growing once the curtain is wider than the valve head, where the throat takes over:
#   A = (pi / 4) * d_valve^2         (per valve)
# This engine draws two valves per port, so both terms carry a factor of 2.
#
# docs/physics-validation.md section 2 lists this as untested. It is checkable without a paywalled source because the
# relation is geometry, not correlation: what CANNOT be checked here is the discharge coefficient's shape against
# lift/diameter (Heywood Fig 6-18, SAE 820154, still gap 4).
#
# Tag [closed]: the capped-curtain relation, not the Cd curve.
# Run: godot --headless --path . -s res://tests/unit/engine/valve_curtain_test.gd   (exit 1 on failure)

const D_EXHAUST := 0.017 # m, the cylinder's default exhaust valve diameter, two valves
const D_INTAKE := 0.020 # m, default intake valve diameter, two valves

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


static func near(a: float, b: float) -> bool:
	return absf(a - b) <= 1.0e-9 * maxf(1.0, absf(b))


# The widest curtain in the cycle and the phase it happens at. The lift curve peaks at its own centre, so the widest
# curtain must be exactly the formula's maximum for the peak lift.
static func widest(c: Cylinder, exhaust: bool) -> Dictionary:
	var best := 0.0
	var at := 0.0
	for phase in range(0, 720, 1):
		var a: float = c.exhaust_valve_area(float(phase)) if exhaust else c._intake_area(float(phase))
		if a > best:
			best = a
			at = float(phase)
	return {"area": best, "phase": at}


static func curtain(d: float, lift: float) -> float:
	return minf(2.0 * PI * d * lift, 0.5 * PI * d * d)


func _make(valve_d: float, lift: float) -> Cylinder:
	var c := Cylinder.new()
	c.setup(62.0, 41.3, 11.5)
	c.exhaust_valve_d = D_EXHAUST
	c.intake_valve_d = D_INTAKE
	if valve_d == D_EXHAUST:
		c.exhaust_lift = lift
	else:
		c.intake_lift = lift
	return c


func _init() -> void:
	# ---- 1. below the cap the widest curtain is exactly 2*pi*d*peak_lift ----
	var lift_low := 0.002
	var c1 := _make(D_EXHAUST, lift_low)
	var w1 := widest(c1, true)
	var want_low := curtain(D_EXHAUST, lift_low)
	check(near(w1.area, want_low),
		"exhaust curtain at %.1f mm lift: %.8f vs 2*pi*d*L = %.8f m2" % [lift_low * 1000.0, w1.area, want_low])

	# ---- 2. above the cap it is the valve head area, not the curtain ----
	var lift_high := 0.02 # 20 mm: the curtain is wider than the valve long before this
	var c2 := _make(D_EXHAUST, lift_high)
	var w2 := widest(c2, true)
	var want_cap := 0.5 * PI * D_EXHAUST * D_EXHAUST
	check(near(w2.area, want_cap), "a tyre-sized lift is capped at the two valve heads (%.8f vs %.8f)" % [w2.area, want_cap])
	check(w2.area < 2.0 * PI * D_EXHAUST * lift_high, "and the capped area is below the uncapped curtain, as it must be")

	# ---- 3. below the cap the area is linear in lift: doubling the lift doubles it ----
	var c3 := _make(D_EXHAUST, lift_low * 2.0)
	var w3 := widest(c3, true)
	check(near(w3.area, 2.0 * w1.area), "doubling the lift doubles the curtain (%.8f vs %.8f)" % [w3.area, 2.0 * w1.area])

	# ---- 4. a shut valve passes nothing, and the event has two edges ----
	check(c1.exhaust_valve_area(0.0) == 0.0, "the exhaust curtain is shut at TDC (phase 0)")
	check(c1.exhaust_valve_area(700.0) == 0.0, "and shut well before the exhaust opens")
	check(c1.exhaust_valve_area(w1.phase) > 0.0, "and open at its own peak (phase %.0f)" % w1.phase)

	# ---- 5. the intake valve gets the same treatment with its own diameter ----
	var ci := _make(D_INTAKE, 0.002)
	var wi := widest(ci, false)
	var want_intake := curtain(D_INTAKE, 0.002)
	check(near(wi.area, want_intake),
		"intake curtain at 2 mm: %.8f vs 2*pi*d*L = %.8f m2" % [wi.area, want_intake])
	check(wi.area > w1.area, "the wider intake valve opens more area than the exhaust at the same lift")

	# ---- 6. the curtain rises and falls once per cycle: no second opening ----
	var opened := 0
	var was_open := false
	for phase in range(0, 720):
		var open: bool = c1.exhaust_valve_area(float(phase)) > 0.0
		if open and not was_open:
			opened += 1
		was_open = open
	check(opened == 1, "the exhaust valve opens once per 720 degree cycle (%d openings)" % opened)

	print("exhaust peak %.8f m2 at phase %.0f, cap %.8f, intake peak %.8f m2 at phase %.0f" % [
		w1.area, w1.phase, want_cap, wi.area, wi.phase])
	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
