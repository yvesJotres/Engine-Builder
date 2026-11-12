extends SceneTree

# Section 3 of docs/physics-validation.md: the two-stroke rows that had no test. These are the five fixes the native
# kernel was ported to, so they are the ones that must not drift back.
#
#   1. burn duration follows engine speed: burn_deg = BURN_DEG_BASE + BURN_DEG_PER_RPM * rpm
#   2. reed valve flow: m = CD * A * sqrt(2*dp/rho) * rho * dt, and nothing at all when the crankcase is above the port
#   3. residual capture at the transfer crossing: the gas already in the cylinder is not fresh air, so the fuel is sized
#      for the difference, and the residual fraction lands strictly between 0 and 1
#   4. crank-radius inertia: the work integral uses stroke/2, so a non-zero recip_kg must change the work - it multiplied
#      by a member that was stuck at 0.0, and the term vanished
#
# Tag [closed]: every expected value is the stated formula.
# Run: godot --headless --path . -s res://tests/unit/engine/two_stroke_state_test.gd   (exit 1 on failure)

const PRESET := "yamaha_rd350"
const DT := 1.0 / 120.0
const P0 := 101325.0

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


static func near(a: float, b: float, tol: float = 1.0e-9) -> bool:
	return absf(a - b) <= tol * maxf(1.0, absf(b))


func _spec() -> EngineSpec:
	var spec := EngineSpec.new()
	var preset: Dictionary = Presets.PRESETS[PRESET]
	for key in preset:
		spec.set(key, preset[key])
	return spec


# Runs whole cycles at a fixed rpm and returns the cylinder after the run.
func _run_cycles(cyl: TwoStrokeCylinder, tank: FuelTank, spec: EngineSpec, rpm: float, cycles: int, spark: bool = true) -> void:
	var dphi := rpm * 6.0 * DT # degrees per frame at this speed
	for i in cycles * int(360.0 / absf(dphi) + 0.5):
		cyl.advance(dphi, DT, P0, 300.0, 340.0, true, tank, 1.0, spark, false, 1.4 * P0, 700.0)


# Accumulates the work advance() returns, which is where the crank-radius inertia term lands.
func _run_for_work(cyl: TwoStrokeCylinder, tank: FuelTank, spec: EngineSpec, rpm: float, cycles: int) -> float:
	var dphi := rpm * 6.0 * DT
	var total := 0.0
	for i in cycles * int(360.0 / absf(dphi) + 0.5):
		total += cyl.advance(dphi, DT, P0, 300.0, 340.0, true, tank, 1.0, true, false, 1.4 * P0, 700.0).x
	return total


func _init() -> void:
	# ---- 1. burn duration is speed-dependent, not frozen at a nominal rpm ----
	var base_speed := TwoStrokeCylinder.burn_duration_deg(0.0)
	var at_6000 := TwoStrokeCylinder.burn_duration_deg(6000.0)
	var at_12000 := TwoStrokeCylinder.burn_duration_deg(12000.0)
	check(base_speed > 0.0, "the burn spans %.1f deg at zero speed" % base_speed)
	check(at_6000 > base_speed, "and %.1f deg at 6000 rpm" % at_6000)
	check(near(at_12000 - base_speed, 2.0 * (at_6000 - base_speed)), "it is linear in rpm (%.2f vs %.2f)" % [at_12000 - base_speed, 2.0 * (at_6000 - base_speed)])
	# a burn that took a fixed number of MILLISECONDS would span more crank degrees as rpm rises: check the slope
	var per_rpm := (at_12000 - at_6000) / 6000.0
	check(per_rpm > 0.0 and per_rpm < 0.01, "%.5f deg per rpm, i.e. about %.2f ms of burn" % [per_rpm, base_speed / 360.0 * 60000.0 / 6000.0])

	# ---- 2. reed flow against the orifice relation ----
	var spec := _spec()
	var cyl := TwoStrokeCylinder.new()
	cyl.setup(spec)
	cyl.start_at(0.0)
	cyl.intake_port_type = "reed"
	var area := cyl.intake_area
	if area > 0.0:
		var intake_p := 1.05 * P0
		var dp: float = intake_p - cyl.crankcase_pressure # against the crankcase, which starts at ambient
		var rho := intake_p / (TwoStrokeCylinder.R * TwoStrokeCylinder.T0)
		var want: float = TwoStrokeCylinder.CD_PORT * area * sqrt(2.0 * dp / rho) * rho * DT
		var got := cyl.reed_flow(intake_p, DT)
		check(near(got, want, 1.0e-9), "reed flow %.10f kg vs hand calc %.10f" % [got, want])
		check(cyl.reed_flow(0.5 * P0, DT) == 0.0, "a port below crankcase pressure draws nothing")
	else:
		check(false, "the preset has no reed area to test")

	# ---- 3. residual capture: a running cycle traps hot gas, so not all of it is fresh air ----
	var tank := FuelTank.new()
	var running := TwoStrokeCylinder.new()
	running.setup(spec)
	running.start_at(0.0)
	# The capture fires at BOTH transfer edges: at the opening edge everything in the cylinder is residual (1.0), at the
	# closing edge the fresh charge from the crankcase has joined it (below 1). Sampling one instant would only ever see
	# whichever edge came last, so the run collects the fraction across the cycle.
	var fractions := []
	var fresh_and_trapped := []
	var dphi := 6000.0 * 6.0 * DT
	var burned := 0.0
	for i in 4 * int(360.0 / absf(dphi) + 0.5):
		var res := running.advance(dphi, DT, P0, 300.0, 340.0, true, tank, 1.0, true, false, 1.4 * P0, 700.0)
		fractions.append(running.last_residual_fraction)
		fresh_and_trapped.append([running.last_fresh_kg, running.mass, running.burn_energy])
		burned = maxf(burned, running.burn_energy)
	check(burned > 0.0, "the cycle actually gets fuel and burns it (%.1f J)" % burned)
	var saw_partial := false
	for f in fractions:
		if float(f) > 0.0 and float(f) < 1.0:
			saw_partial = true
	check(saw_partial, "the trapped charge is part residual, part fresh (fraction below 1)")
	# Note: last_fresh_kg and mass cannot be compared ACROSS a frame - the charge is measured at the closing edge and mass
	# keeps falling through the exhaust afterwards. The clamp to trapped happens inside _fuel_charge, so what is checkable
	# from outside is that a fresh charge arrived at all and that the residual fraction is a real fraction.
	var any_fresh := false
	for pair in fresh_and_trapped:
		if float(pair[0]) > 0.0:
			any_fresh = true
	check(any_fresh, "a fresh charge arrives during the scavenge window")
	check(running.last_ivc_temp > 0.0, "and the state is read at the crossing (%.0f K)" % running.last_ivc_temp)
	check(tank.mass_kg < 8.94, "the tank is being drawn down (%.6f kg)" % tank.mass_kg)

	# ---- 4. crank-radius inertia: recip_kg must reach the work integral ----
	var light := TwoStrokeCylinder.new()
	light.setup(spec)
	light.start_at(0.0)
	light.recip_kg = 0.0
	var light_tank := FuelTank.new()
	var light_work := _run_for_work(light, light_tank, spec, 6000.0, 3)

	var heavy := TwoStrokeCylinder.new()
	heavy.setup(spec)
	heavy.start_at(0.0)
	heavy.recip_kg = 0.45 # kg, a plausible piston and rod share
	var heavy_tank := FuelTank.new()
	var heavy_work := _run_for_work(heavy, heavy_tank, spec, 6000.0, 3)
	check(absf(light_work) > 0.0, "the run returned work (%.3f J)" % light_work)
	# The inertia term is added to the returned work, not to the pressure integral that IMEP reports, so this is the
	# quantity it can actually move - which is why the check is on work and not on last_imep.
	check(not is_equal_approx(light_work, heavy_work),
		"reciprocating mass changes the work the rod does (%.3f vs %.3f J)" % [light_work, heavy_work])

	print("burn %.1f deg at 6000 rpm (%.1f at 0); work light %.3f vs heavy %.3f J" % [
		at_6000, base_speed, light_work, heavy_work])
	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
