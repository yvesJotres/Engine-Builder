class_name Cylinder
extends RefCounted

# Single cylinder, four-stroke, stepped in crank angle.
# Phase phi (deg): 0 = firing TDC, 180 = BDC after the power stroke, 360 = exhaust TDC,
# 540 = intake BDC, 720 = firing TDC again. Gas state (mass, temperature, pressure) comes from
# the first law with mass flows through the valves. Torque comes from the gas pressure on the piston.

const G := 1.4
const R := 287.0
const CV := R / (G - 1.0)
const CP := G * R / (G - 1.0)
const CV_BURNT := 960.0 # J/(kg·K), combustion products (gamma about 1.3), estimate; air's CV is 717.5
const P0 := 101325.0 # atmosphere, Pa
const T0 := 300.0 # intake and ambient temperature, K
const CD_VALVE := 0.7 # discharge coefficient for valve curtain flow, estimate
const COMBUSTION_EFFICIENCY := 0.95 # estimate
const MISFIRE_LAMBDA := 1.35
const BURN_DEG_BASE := 45.0 # crank degrees of burn at zero rpm, estimate
const BURN_DEG_PER_RPM := 0.002 # the flame takes about the same time in ms, so the burn spans more crank degrees as rpm rises, estimate
const CA50_TARGET := 10.0 # deg after TDC where half the charge is burnt, near best torque (typical 8 to 12)
const WIEBE_CA50 := 0.465 # Wiebe point where 50% is burnt, as a share of the burn duration
const WIEBE_A := 6.908 # Wiebe efficiency factor, 99.9% burnt at the end of the burn duration
const WIEBE_M := 2.0 # Wiebe form factor, slow start, fast middle, slow end
const STEP_DEG := 5.0 # cylinder integration step, deg, coarse enough to run at 60 fps
const WALL_HEAT := 1000.0 # W/(m²·K), average heat transfer to the walls at WALL_REF_W, typical engine value
const WALL_REF_W := 314.0 # rad/s, 3000 rpm, the speed WALL_HEAT applies at
const WALL_TEMP := 420.0 # K, cylinder wall temperature, estimate

# valve timing (deg, phi): intake open 350 to close 580, exhaust open 140 to close 370
const INTAKE_OPEN := 350.0
const INTAKE_CLOSE := 590.0
const EXHAUST_OPEN := 140.0
const EXHAUST_CLOSE := 370.0
const INTAKE_LIFT := 0.006 # m, peak lift, estimate
const EXHAUST_LIFT := 0.005 # m, peak lift, estimate
const INTAKE_VALVE_D := 0.020 # m, per valve (2 valves), estimate
const EXHAUST_VALVE_D := 0.017 # m, per valve (2 valves), estimate
const INTAKE_PORT_AREA := 2.0 * PI * 0.0125 * 0.0125 # m², estimate
const EXHAUST_PORT_AREA := 2.0 * PI * 0.0105 * 0.0105 # m², estimate
# Intake runner between the manifold and the valve: the air column has inertia (A/L), the port holds gas (volume).
# That lumped resonance is what makes volumetric efficiency rise to a peak at one engine speed (ram tuning).
const RUNNER_AREA := 6.6e-4 # m², runner cross-section, 29 mm bore, estimate
const RUNNER_LENGTH := 0.25 # m, throttle body to valve, estimate
const PORT_VOLUME := 0.5e-4 # m³, effective port and runner gas volume, estimate, sets the tuned rpm
const RUNNER_LOSS := 1.5 # dynamic-pressure loss coefficient of the runner, estimate
const MAX_FLOW_DT := 2.5e-4 # s, longest port step, the port volume is stiff against the valve flow

var swept := 0.0 # m³
var clearance := 0.0 # m³
var bore := 0.0 # m
var piston_area := 0.0 # m²
var stroke := 0.0 # m
var recip_kg := 0.15 # piston plus rod small end, kg
var rod_ratio := 1.6 # rod length over crank radius
var phi := 0.0 # unwrapped crank angle, deg
var mass := 0.0 # kg of gas in the cylinder
var temp := T0 # K
var pressure := P0 # Pa
var burn_energy_left := 0.0 # J still to release in this cycle
var burn_energy := 0.0 # J released by the charge in this cycle, total
var port_p := P0 # Pa, gas pressure at the intake valve
var runner_q := 0.0 # kg/s, flow along the runner toward the cylinder
var _residual_kg := 0.0 # kg of burnt gas left in the cylinder when the exhaust valve closed
var _burnt := 0.0 # share of this cycle's fuel energy released so far, 0 = fresh air, 1 = all burnt
var wall_loss_j := 0.0 # J of heat lost to the walls since the cylinder was made
var _u := 0.0 # J, internal energy of the gas: the state that carries from step to step, temperature follows from it
var enthalpy_in_j := 0.0 # J of gas enthalpy brought in since the cylinder was made
var enthalpy_out_j := 0.0 # J of gas enthalpy carried out since the cylinder was made


func setup(bore_mm: float, stroke_mm: float, compression_ratio: float, recip: float = 0.15, rod_lambda: float = 1.6) -> void:
	bore = bore_mm * 0.001
	piston_area = PI * bore * bore / 4.0
	stroke = stroke_mm * 0.001
	swept = piston_area * stroke
	recip_kg = recip
	rod_ratio = rod_lambda
	clearance = swept / (compression_ratio - 1.0)
	pressure = P0
	temp = T0
	mass = pressure * (clearance + swept) / (R * temp)
	_u = mass * CV * temp
	phi = 0.0
	port_p = P0
	runner_q = 0.0


# Puts the piston at a phase with the gas at atmospheric pressure, so the start state matches the volume.
func start_at(phase_deg: float) -> void:
	phi = fposmod(phase_deg, 720.0)
	mass = pressure * volume(phi) / (R * temp)
	_u = mass * CV * temp


# Cylinder volume at phase phi, m³.
func volume(phi_deg: float) -> float:
	return clearance + swept * 0.5 * (1.0 - cos(deg_to_rad(phi_deg)))


# Valve lift at phase phi: half-sine between open and close, zero when shut.
static func lift(phi_deg: float, open_deg: float, close_deg: float, peak: float) -> float:
	var p := fmod(phi_deg, 720.0)
	if p < open_deg or p > close_deg:
		return 0.0
	return peak * sin(PI * (p - open_deg) / (close_deg - open_deg))


# Signed mass flow, kg/s, from side 1 to side 2 through an orifice of this area.
static func mass_flow(area: float, p1: float, t1: float, p2: float, t2: float) -> float:
	if area <= 0.0:
		return 0.0
	if p1 >= p2:
		return _subsonic(area, p1, t1, p2)
	return -_subsonic(area, p2, t2, p1)


static func _subsonic(area: float, p_up: float, t_up: float, p_down: float) -> float:
	var pr := p_down / p_up
	var k := CD_VALVE * area * p_up / sqrt(R * t_up)
	var crit := pow(2.0 / (G + 1.0), G / (G - 1.0))
	if pr <= crit:
		return k * sqrt(G * pow(2.0 / (G + 1.0), (G + 1.0) / (G - 1.0)))
	return k * sqrt(2.0 * G / (G - 1.0) * (pow(pr, 2.0 / G) - pow(pr, (G + 1.0) / G)))


# Advances the cylinder by dphi degrees, taking dt seconds. pm and tm: manifold pressure and temperature.
# ign_phi: spark phase. firing: the engine is running. tank: fuel is drawn when the intake valve closes.
# Returns Vector2(average gas torque over dphi in N·m, mass drawn from the manifold in kg).
func advance(dphi: float, dt: float, pm: float, tm: float, ign_phi: float, firing: bool,
		tank: FuelTank, lambda: float) -> Vector2:
	var steps := maxi(1, maxi(ceili(absf(dphi) / STEP_DEG), ceili(dt / MAX_FLOW_DT)))
	var sd := dphi / steps
	var sdt := dt / steps
	var work := 0.0
	var theta := 0.0
	var drawn := 0.0
	var w := deg_to_rad(dphi) / dt if dt > 0.0 else 0.0 # crank speed, rad/s
	var crank_r := stroke * 0.5
	var burn_deg := burn_duration_deg(w * 60.0 / TAU)
	for i in steps:
		var p0 := phi
		var p1 := phi + sd
		var dv := volume(p1) - volume(p0)
		if _crossed(p0, p1, INTAKE_OPEN):
			_burnt = 0.0 # a new cycle starts with fresh air

		# runner: the air column accelerates under the manifold-to-port pressure difference, then the port feeds the valve
		var v_run := runner_q / (RUNNER_AREA * 1.2)
		runner_q += RUNNER_AREA / RUNNER_LENGTH * (pm - port_p - 0.5 * RUNNER_LOSS * 1.2 * v_run * absf(v_run)) * sdt
		var m_in := mass_flow(minf(2.0 * PI * INTAKE_VALVE_D * lift(p0, INTAKE_OPEN, INTAKE_CLOSE, INTAKE_LIFT), INTAKE_PORT_AREA), port_p, tm, pressure, temp) * sdt
		port_p = clampf(port_p + R * tm / PORT_VOLUME * (runner_q * sdt - m_in), 1000.0, 3.0 * P0)
		var m_out := mass_flow(minf(2.0 * PI * EXHAUST_VALVE_D * lift(p0, EXHAUST_OPEN, EXHAUST_CLOSE, EXHAUST_LIFT), EXHAUST_PORT_AREA), pressure, temp, P0, T0) * sdt

		# exhaust valve closes: what is left in the cylinder is burnt gas from the last cycle, not fresh air
		if _crossed(p0, p1, EXHAUST_CLOSE):
			_residual_kg = mass

		# intake valve closes: the fresh air that came in sets how much fuel is injected and burned
		if firing and _crossed(p0, p1, INTAKE_CLOSE):
			_fuel_charge(tank, lambda)

		# combustion heat, released over the burn duration starting at the spark
		var dq := 0.0
		if firing and burn_energy_left > 0.0 and _in_window(p0, ign_phi, burn_deg):
			var rel := fmod(p0 - ign_phi + 720.0, 720.0)
			dq = minf(burn_energy_left, burn_energy * (_wiebe(rel + sd, burn_deg) - _wiebe(rel, burn_deg)))
			burn_energy_left -= dq
			_burnt = 1.0 - burn_energy_left / burn_energy

		# heat lost to the walls: head plus piston crown plus the liner exposed by the piston
		var liner := (volume(p1) - clearance) / piston_area
		var wall_area := 2.0 * piston_area + PI * bore * maxf(liner, 0.0)
		# wall heat transfer grows with gas motion (Woschni-like, speed^0.8), so it is small when cranking
		var h_wall := WALL_HEAT * pow(maxf(w, 1.0) / WALL_REF_W, 0.8)
		var q_loss := h_wall * wall_area * (temp - WALL_TEMP) * sdt
		wall_loss_j += q_loss # running total, for the combustion checks

		# first law for the gas in the cylinder
		# the heat capacity moves from air to combustion products as the charge burns (CV_BURNT once it is all burnt)
		var cv := CV + _burnt * (CV_BURNT - CV)
		var cp := cv + R
		var h_in := cp * (tm if m_in >= 0.0 else temp) * m_in
		enthalpy_in_j += h_in # running totals, for the energy balance check
		enthalpy_out_j += cp * temp * m_out
		var u := _u - pressure * dv + dq + h_in - cp * temp * m_out - q_loss
		mass = maxf(mass + m_in - m_out, 1e-12)
		# guard: a single step must never push the gas outside physical limits
		temp = clampf(u / (mass * cv), 200.0, 4000.0)
		_u = mass * cv * temp
		pressure = clampf(mass * R * temp / volume(p1), 1000.0, 1.0e7)

		var dtheta := sd * PI / 180.0
		work += (pressure - P0) * dv
		# inertia of the moving piston and rod: a = r·ω²·(cos φ + cos 2φ / λ), torque = -m·a·r·sin φ
		var phi_r := deg_to_rad(p0)
		var accel_term := cos(phi_r) + cos(2.0 * phi_r) / rod_ratio
		work += -recip_kg * crank_r * crank_r * w * w * accel_term * sin(phi_r) * dtheta
		theta += dtheta
		drawn += runner_q * sdt
		phi = p1
	return Vector2(work / theta if theta > 0.0 else 0.0, drawn)


func _fuel_charge(tank: FuelTank, lambda: float) -> void:
	burn_energy = 0.0
	burn_energy_left = 0.0
	if lambda >= MISFIRE_LAMBDA:
		return # too lean to light
	var fresh := maxf(mass - _residual_kg, 0.0) # the burnt gas left from the last cycle takes no fuel
	var wanted := fresh / (tank.afr * lambda)
	var supplied := minf(wanted, tank.mass_kg)
	tank.mass_kg -= supplied
	mass += supplied # the fuel joins the charge, so the gas carries the mass it releases energy from
	_u += supplied * CV * temp # at the gas temperature, so the mix stays at the same temperature
	burn_energy = supplied * tank.lhv * COMBUSTION_EFFICIENCY
	burn_energy_left = burn_energy


# Crank degrees from spark to the end of the burn at this speed. Shared with the spark timing in EngineAir.
static func burn_duration_deg(rpm: float) -> float:
	return BURN_DEG_BASE + BURN_DEG_PER_RPM * rpm


# Fraction of the charge burnt at this many degrees after the spark.
static func _wiebe(rel: float, burn_deg: float) -> float:
	return 1.0 - exp(-WIEBE_A * pow(clampf(rel / burn_deg, 0.0, 1.0), WIEBE_M + 1.0))


static func _crossed(a: float, b: float, at: float) -> bool:
	return floor((b - at) / 720.0) > floor((a - at) / 720.0)


static func _in_window(p: float, start: float, length: float) -> bool:
	var rel := fmod(p - start + 720.0, 720.0)
	return rel < length
