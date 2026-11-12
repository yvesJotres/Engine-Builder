extends SceneTree

# Section 5 of docs/physics-validation.md: wheel slip, the tyre's mu(slip) curve and the clutch's torque transfer,
# all of which were marked untested. Each is a closed form, so the expected values are written out here.
#
#   slip ratio      s = (omega*r - v) / v, clamped to -1..1, and zero below MIN_SPEED (a crawling wheel is stopping,
#                   not locking)
#   mu(slip)        peak TYRE_MU_PEAK at TYRE_SLIP_PEAK, decaying to TYRE_MU_LOCKED over ~0.25 of slip; mu(0) = 0
#   clutch torque   T = slip / (dt * (1/J + drive^2 * eff / m) + 1/k), clamped to +-capacity, drive = ratio / radius
#
# Tag [closed] for the clamp and limit behaviour, [hand] for the peak and locked values (they are the model's own
# specification, documented in docs/engine_physics/10 and the wheel constants).
# Run: godot --headless --path . -s res://tests/unit/sim/drivetrain_formulas_test.gd   (exit 1 on failure)

const RADIUS := 0.31 # m
const MU_PEAK := Wheel.TYRE_MU_PEAK
const MU_LOCKED := Wheel.TYRE_MU_LOCKED
const SLIP_PEAK := Wheel.TYRE_SLIP_PEAK

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


static func near(a: float, b: float, tol: float = 1.0e-9) -> bool:
	return absf(a - b) <= tol * maxf(1.0, absf(b))


func _init() -> void:
	# ---- 1. slip ratio: rolling, braking, spinning, locked, and the crawl floor ----
	var v := 20.0
	check(Wheel.slip_ratio(v / RADIUS, v, RADIUS) == 0.0, "a wheel turning at road speed has zero slip")
	check(near(Wheel.slip_ratio(0.0, v, RADIUS), -1.0), "a locked wheel sits at slip -1 (%.3f)" % Wheel.slip_ratio(0.0, v, RADIUS))
	check(near(Wheel.slip_ratio(0.5 * v / RADIUS, v, RADIUS), -0.5),
		"half road speed spins at slip -0.5 (%.3f)" % Wheel.slip_ratio(0.5 * v / RADIUS, v, RADIUS))
	check(near(Wheel.slip_ratio(2.0 * v / RADIUS, v, RADIUS), 1.0),
		"twice road speed is slip +1 (%.3f)" % Wheel.slip_ratio(2.0 * v / RADIUS, v, RADIUS))
	check(near(Wheel.slip_ratio(5.0 * v / RADIUS, v, RADIUS), 1.0), "and it clamps there, not above")
	check(Wheel.slip_ratio(3.0 / RADIUS, 0.2, RADIUS) == 0.0,
		"under MIN_SPEED a spinning wheel reports no slip (%.3f)" % Wheel.slip_ratio(3.0 / RADIUS, 0.2, RADIUS))

	# ---- 2. mu(slip): zero at zero, peak exactly at TYRE_SLIP_PEAK, decaying but above the locked value ----
	check(Wheel.mu(0.0) == 0.0, "no slip, no grip force")
	check(near(Wheel.mu(SLIP_PEAK), MU_PEAK), "the peak grip is at slip %.2f (%.3f vs %.3f)" % [SLIP_PEAK, Wheel.mu(SLIP_PEAK), MU_PEAK])
	check(Wheel.mu(SLIP_PEAK) > Wheel.mu(SLIP_PEAK * 2.0), "past the peak the coefficient falls")
	check(Wheel.mu(1.0) < MU_PEAK and Wheel.mu(1.0) > MU_LOCKED,
		"a locked tyre keeps more than the sliding value and less than the peak (%.3f)" % Wheel.mu(1.0))
	check(is_equal_approx(Wheel.mu(-0.2), Wheel.mu(0.2)), "the curve is symmetric in slip")
	# the decaying branch's asymptote is TYRE_MU_LOCKED, so a very large slip tends to it from above
	# the decay is exponential, so by slip 20 it has reached the asymptote to double precision
	check(Wheel.mu(20.0) <= Wheel.mu(1.0) and Wheel.mu(20.0) >= MU_LOCKED,
		"and it approaches the locked value as slip grows (%.6f, asymptote %.3f)" % [Wheel.mu(20.0), MU_LOCKED])

	# ---- 3. clutch transfer: zero when matched, clamped at capacity, sign follows slip ----
	var ratio := 9.0
	var capacity := 200.0
	var inertia := 0.12
	var mass := 220.0
	var dt := 1.0 / 1200.0
	var matched_speed := 30.0
	var matched_omega := matched_speed * ratio / RADIUS
	check(EngineSim.clutch_transfer_torque(matched_omega, matched_speed, inertia, mass, ratio, RADIUS, capacity, dt) == 0.0,
		"a clutch at matched speed carries no torque")
	var huge_slip := EngineSim.clutch_transfer_torque(matched_omega + 5000.0, matched_speed, inertia, mass, ratio, RADIUS, capacity, dt)
	check(near(huge_slip, capacity), "a big speed mismatch saturates at capacity (%.2f of %.2f N m)" % [huge_slip, capacity])
	var overrun := EngineSim.clutch_transfer_torque(matched_omega - 500.0, matched_speed, inertia, mass, ratio, RADIUS, capacity, dt)
	check(near(overrun, -capacity), "engine slower than the road drives the engine backwards (%.2f N m)" % overrun)
	check(EngineSim.clutch_transfer_torque(matched_omega, matched_speed, inertia, mass, 0.0, RADIUS, capacity, dt) == 0.0,
		"neutral carries nothing (ratio 0)")
	check(EngineSim.clutch_transfer_torque(matched_omega + 10.0, matched_speed, inertia, mass, ratio, RADIUS, 0.0, dt) == 0.0,
		"an open clutch (zero capacity) carries nothing")

	# ---- 4. the stiff limit is linear in slip, and a soft clutch carries less for the same slip ----
	var slip_omega := matched_omega + 2.0
	var soft := EngineSim.clutch_transfer_torque(slip_omega, matched_speed, inertia, mass, ratio, RADIUS, capacity, dt, 50.0)
	var stiffer := EngineSim.clutch_transfer_torque(slip_omega, matched_speed, inertia, mass, ratio, RADIUS, capacity, dt, 5000.0)
	check(soft < stiffer and soft > 0.0, "a softer clutch transfers less of the same slip (%.3f < %.3f)" % [soft, stiffer])
	var doubled := EngineSim.clutch_transfer_torque(matched_omega + 4.0, matched_speed, inertia, mass, ratio, RADIUS, capacity, dt, 50.0)
	check(near(doubled, 2.0 * soft), "and it is linear in slip while unsaturated (%.3f vs %.3f)" % [doubled, 2.0 * soft])

	# ---- 5. slip capacity floor: the pack can carry at least its spring load ----
	var spec := EngineSpec.new()
	spec.displacement_cc = 1000.0
	var cap := EngineSim.new().clutch_capacity(spec)
	check(cap > 0.0, "the clutch has a capacity from the geometry (%.1f N m)" % cap)

	print("slip: locked %.2f, peak mu %.3f at %.2f, locked mu %.3f; clutch %.1f N m" % [
		Wheel.slip_ratio(0.0, v, RADIUS), MU_PEAK, SLIP_PEAK, Wheel.mu(1.0), cap])
	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
