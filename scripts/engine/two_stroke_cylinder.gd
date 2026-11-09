class_name TwoStrokeCylinder
extends RefCounted

# Two-stroke cylinder: crankcase compression + cylinder combustion in one 360° cycle
# Phase phi (deg): 0 = firing TDC, 180 = BDC, 360 = firing TDC again
# Uses crankcase as pump: intake -> crankcase -> transfer ports -> cylinder -> exhaust port

const G := 1.4
const R := 287.0
const CV := R / (G - 1.0)
const CP := G * R / (G - 1.0)
const CV_BURNT := 960.0 # J/(kg·K), combustion products (gamma ~1.3)
const P0 := 101325.0
const T0 := 300.0
const CD_PORT := 0.7 # discharge coefficient for port flow
const COMBUSTION_EFFICIENCY := 0.93
const MISFIRE_LAMBDA := 1.3
const BURN_DEG_BASE := 35.0
const BURN_DEG_PER_RPM := 0.0015
const CA50_TARGET := 12.0
const WIEBE_CA50 := 0.465
const WIEBE_A := 6.908
const WIEBE_M := 2.0
const STEP_DEG := 5.0 # finer step for 2-stroke (360° cycle)
const WALL_HEAT := 1200.0 # higher heat transfer (more frequent combustion)
const WALL_REF_W := 314.0
const WALL_TEMP := 450.0
const OIL_FUEL_RATIO_BASE := 50.0 # reference ratio for oil mixing

# Port timing (deg ATDC = after TDC on power stroke)
var transfer_open := 120.0
var transfer_close := 150.0
var exhaust_open := 90.0
var exhaust_close := 90.0
var intake_open := 60.0
var intake_close := 60.0

# Intake port type: "reed", "rotary", or "piston"
var intake_port_type: String = "piston"

# Port areas (m²)
var transfer_area := 0.0
var exhaust_area := 0.0
var intake_area := 0.0

# Crankcase
var crankcase_volume := 0.0
var crankcase_mass := 0.0
var crankcase_temp := T0
var crankcase_pressure := P0

# Cylinder state
var swept := 0.0
var clearance := 0.0
var bore := 0.0
var piston_area := 0.0
var stroke := 0.0
var recip_kg := 0.15
var rod_ratio := 1.6
var phi := 0.0
var mass := 0.0
var temp := T0
var pressure := P0
var burn_energy_left := 0.0
var burn_energy := 0.0
var port_p := P0
var runner_q := 0.0
var exhaust_temp := 300.0
var peak_temp := 300.0
var last_peak_temp := 300.0
var last_lambda := 1.0
var _fired := false
var fuel_unburnt_kg := 0.0
var _port_heat := T0
var backfire_j := 0.0
var _residual_kg := 0.0
var _overlap_out := 0.0
var _burnt := 0.0
var wall_loss_j := 0.0
var _u := 0.0
var enthalpy_in_j := 0.0
var enthalpy_out_j := 0.0
var exhaust_mdot := 0.0
var exhaust_power := 0.0
var _cycle_work := 0.0
var _cycle_deg := 0.0
var _cycle_peak_p := 0.0
var _cycle_max_dp := 0.0
var _cycle_p := 0.0
var _ca10 := -1.0
var _ca50 := -1.0
var _ca90 := -1.0
var last_imep := 0.0
var last_peak_pressure := 0.0
var last_dp_dtheta := 0.0
var last_ca10 := -1.0
var last_ca50 := -1.0
var last_ca90 := -1.0
var last_burn_10_90 := 0.0
var last_fresh_kg := 0.0
var last_ivc_temp := T0
var last_residual_fraction := 0.0

# Oil injection
var oil_ratio := 50.0
var oil_in_crankcase_kg := 0.0

func setup(spec: EngineSpec) -> void:
	bore = spec.bore_mm * 0.001
	piston_area = PI * bore * bore / 4.0
	stroke = spec.stroke_mm * 0.001
	swept = piston_area * stroke
	recip_kg = spec.reciprocating_kg()
	rod_ratio = spec.rod_ratio
	clearance = swept / (spec.compression_ratio - 1.0)

	# Crankcase volume from compression ratio
	if spec.crankcase_volume_cc > 0.0:
		crankcase_volume = spec.crankcase_volume_cc * 1e-6
	else:
		crankcase_volume = swept * spec.crankcase_compression_ratio

	# Port areas from spec (mm² to m²)
	transfer_area = maxf(spec.transfer_port_area_mm2, 0.0) * 1e-6
	exhaust_area = maxf(spec.exhaust_port_area_mm2, 0.0) * 1e-6
	intake_area = maxf(spec.intake_port_area_mm2, 0.0) * 1e-6

	# Port timing
	transfer_open = spec.transfer_port_open_deg
	transfer_close = 360.0 - spec.transfer_port_close_deg
	exhaust_open = spec.exhaust_port_open_deg
	exhaust_close = 360.0 - spec.exhaust_port_close_deg

	intake_port_type = spec.intake_port_type
	if intake_port_type == "reed":
		# Reed valve: opens when crankcase pressure < intake pressure
		intake_open = 0.0
		intake_close = 360.0
	elif intake_port_type == "rotary":
		intake_open = spec.intake_port_open_deg
		intake_close = 360.0 - spec.intake_port_close_deg
	else: # piston port
		intake_open = spec.intake_port_open_deg
		intake_close = 360.0 - spec.intake_port_close_deg

	oil_ratio = spec.oil_injection_ratio

	pressure = P0
	temp = T0
	mass = pressure * clearance / (R * temp)
	_u = mass * CV * temp
	phi = 0.0
	port_p = P0
	runner_q = 0.0

	# Crankcase initial state
	crankcase_pressure = P0
	crankcase_temp = T0
	crankcase_mass = crankcase_pressure * crankcase_volume / (R * crankcase_temp)

	oil_in_crankcase_kg = 0.0


func start_at(phase_deg: float) -> void:
	phi = fposmod(phase_deg, 360.0)
	mass = pressure * volume(phi) / (R * temp)
	_u = mass * CV * temp


func volume(phi_deg: float) -> float:
	var angle := deg_to_rad(phi_deg)
	var crank_radius := stroke * 0.5
	var rod_length := rod_ratio * crank_radius
	var crank_offset := crank_radius * sin(angle)
	var displacement := crank_radius * (1.0 - cos(angle)) + rod_length - sqrt(rod_length * rod_length - crank_offset * crank_offset)
	return clearance + piston_area * displacement


# Crankcase volume (changes with piston position)
func crankcase_vol(phi_deg: float) -> float:
	var angle := deg_to_rad(phi_deg)
	var crank_radius := stroke * 0.5
	var rod_length := rod_ratio * crank_radius
	var crank_offset := crank_radius * sin(angle)
	var displacement := crank_radius * (1.0 - cos(angle)) + rod_length - sqrt(rod_length * rod_length - crank_offset * crank_offset)
	# Crankcase volume is max at TDC, min at BDC (opposite of cylinder)
	return crankcase_volume - piston_area * displacement


# Port area at phase (simple step function for piston ports, reed valve for intake)
func transfer_port_area(phase_deg: float) -> float:
	var p := fposmod(phase_deg, 360.0)
	if p >= transfer_open and p <= transfer_close:
		return transfer_area
	return 0.0


func exhaust_port_area(phase_deg: float) -> float:
	var p := fposmod(phase_deg, 360.0)
	if p >= exhaust_open and p <= exhaust_close:
		return exhaust_area
	return 0.0


func intake_port_area(phase_deg: float) -> float:
	if intake_area <= 0.0:
		return 0.0
	var p := fposmod(phase_deg, 360.0)
	if p >= intake_open and p <= intake_close:
		return intake_area
	# Reed valve: opens when crankcase pressure < intake pressure
	return 0.0


# Reed valve flow (simplified)
func reed_flow(intake_p: float, dt: float) -> float:
	if intake_area <= 0.0:
		return 0.0
	var delta_p := intake_p - crankcase_pressure
	if delta_p <= 0.0:
		return 0.0
	# Simple mass flow through reed
	var rho := intake_p / (R * T0)
	return CD_PORT * intake_area * sqrt(2.0 * delta_p / rho) * rho * dt


static func mass_flow(area: float, p1: float, t1: float, p2: float, t2: float) -> float:
	if area <= 0.0:
		return 0.0
	if p1 >= p2:
		return _subsonic(area, p1, t1, p2)
	return -_subsonic(area, p2, t2, p1)


static func _subsonic(area: float, p_up: float, t_up: float, p_down: float) -> float:
	var pr := p_down / p_up
	var k := CD_PORT * area * p_up / sqrt(R * t_up)
	var crit := pow(2.0 / (G + 1.0), G / (G - 1.0))
	if pr <= crit:
		return k * sqrt(G * pow(2.0 / (G + 1.0), (G + 1.0) / (G - 1.0)))
	return k * sqrt(2.0 * G / (G - 1.0) * (pow(pr, 2.0 / G) - pow(pr, (G + 1.0) / G)))


# Advance by dphi degrees in dt seconds
# Returns Vector2(cycle_work, fuel_consumed_kg)
func advance(dphi: float, dt: float, intake_p: float, intake_temp: float, ign_phi: float, running: bool,
		fuel_tank: FuelTank, lambda: float, spark: bool, limiter_cut: bool,
		expansion_chamber_p: float = P0, expansion_chamber_temp: float = T0) -> Vector2:

	var steps := maxi(1, maxi(ceili(absf(dphi) / STEP_DEG), ceili(dt / 1e-4)))
	var sd := dphi / steps
	var sdt := dt / steps
	var work := 0.0
	var fuel_consumed := 0.0

	for i in steps:
		var p0 := phi
		var p1 := phi + sd
		var next_vol := volume(p1)
		var dv := next_vol - volume(p0)

		# Crankcase volume change
		var cc_vol0 := crankcase_vol(p0)
		var cc_vol1 := crankcase_vol(p1)
		var cc_dv := cc_vol1 - cc_vol0

		# Check port events
		var transfer_open_now := (p0 < transfer_open and p1 >= transfer_open) or (p0 <= transfer_close and p1 > transfer_close)
		var exhaust_open_now := (p0 < exhaust_open and p1 >= exhaust_open) or (p0 <= exhaust_close and p1 > exhaust_close)

		# 1. Intake / Reed valve flow into crankcase
		if intake_area > 0.0:
			if intake_port_type == "reed":
				# Reed valve flow
				var m_in := reed_flow(intake_p, sdt)
				crankcase_mass += m_in
				crankcase_pressure = crankcase_mass * R * crankcase_temp / cc_vol1
				enthalpy_in_j += m_in * CP * intake_temp
			elif intake_port_type == "rotary" or intake_port_type == "piston":
				# Piston/rotary port - use port area function
				var a := intake_port_area(p0)
				if a > 0.0:
					var m_in := mass_flow(a, intake_p, intake_temp, crankcase_pressure, crankcase_temp) * sdt
					crankcase_mass += m_in
					crankcase_pressure = crankcase_mass * R * crankcase_temp / cc_vol1
					enthalpy_in_j += m_in * CP * intake_temp

		# 2. Crankcase compression/expansion (adiabatic)
		if cc_dv != 0.0:
			# Work done on crankcase gas
			var cc_work := crankcase_pressure * cc_dv
			# Adiabatic compression: P*V^gamma = const, so T2/T1 = (V1/V2)^(gamma-1)
			var t_ratio := pow(maxf(cc_vol0 / cc_vol1, 1e-6), G - 1.0)
			crankcase_temp *= t_ratio
			crankcase_pressure = crankcase_mass * R * crankcase_temp / cc_vol1

		# 3. Transfer port flow (crankcase -> cylinder)
		var transfer_a := transfer_port_area(p0)
		if transfer_a > 0.0:
			var m_transfer := mass_flow(transfer_a, crankcase_pressure, crankcase_temp, pressure, temp) * sdt
			# Oil mixes with transfer charge
			var oil_mass := m_transfer * (1.0 / oil_ratio) if oil_ratio > 0.0 else 0.0
			oil_in_crankcase_kg -= oil_mass
			mass += m_transfer + oil_mass
			crankcase_mass -= m_transfer
			crankcase_pressure = crankcase_mass * R * crankcase_temp / cc_vol1
			# Energy transfer
			var h_in := CP * crankcase_temp * m_transfer
			_u += h_in
			enthalpy_in_j += h_in

		# 3b. Check if transfer ports just closed - inject fuel
		if transfer_open_now:
			_fuel_charge(fuel_tank, lambda, spark, limiter_cut, intake_p)

		# 4. Exhaust port flow (cylinder -> expansion chamber / atmosphere)
		var exhaust_a := exhaust_port_area(p0)
		var p_ex := expansion_chamber_p
		var t_ex := expansion_chamber_temp
		if exhaust_a > 0.0:
			var m_out := mass_flow(exhaust_a, pressure, temp, p_ex, t_ex) * sdt
			mass -= m_out
			# Energy out
			var h_out := CP * temp * m_out
			_u -= h_out
			enthalpy_out_j += h_out
			exhaust_mdot = m_out / sdt
			exhaust_power = h_out / sdt

		# 5. Combustion
		var dq := 0.0
		if spark and burn_energy_left > 0.0 and _in_burn_window(p0, ign_phi):
			var rel := fmod(p0 - ign_phi + 360.0, 360.0)
			dq = minf(burn_energy_left, burn_energy * (_wiebe(rel + sd) - _wiebe(rel)))
			burn_energy_left -= dq
			_u += dq # the released heat goes into the gas: without it the burn never raised the pressure
			_burnt = 1.0 - burn_energy_left / burn_energy

		# 6. Wall heat transfer
		var liner := (next_vol - clearance) / piston_area
		var wall_area := 2.0 * piston_area + PI * bore * maxf(liner, 0.0)
		var w := absf(phi * PI / 180.0) # rough crank speed estimate
		var h_wall := WALL_HEAT * pow(maxf(w, 1.0) / WALL_REF_W, 0.8)
		var q_loss := h_wall * wall_area * (temp - WALL_TEMP) * sdt
		wall_loss_j += q_loss
		_u -= q_loss

		# 7. First law
		mass = maxf(mass, 1e-12)
		temp = clampf(_u / (mass * CV), 200.0, 4000.0)
		_u = mass * CV * temp
		peak_temp = maxf(peak_temp, temp)
		pressure = clampf(mass * R * temp / next_vol, 1000.0, 1.0e7)

		# Cycle work integral
		var dtheta := sd * PI / 180.0
		work += (pressure - P0) * dv
		# Inertia torque
		var phi_r := deg_to_rad(p0)
		var accel_term := cos(phi_r) + cos(2.0 * phi_r) / rod_ratio
		work += -recip_kg * crank_radius * crank_radius * w * w * accel_term * sin(phi_r) * dtheta

		# Track combustion phasing
		if _ca10 < 0.0 and _burnt >= 0.1:
			_ca10 = p1
		if _ca50 < 0.0 and _burnt >= 0.5:
			_ca50 = p1
		if _ca90 < 0.0 and _burnt >= 0.9:
			_ca90 = p1

		_cycle_work += pressure * dv
		_cycle_deg += sd
		_cycle_peak_p = maxf(_cycle_peak_p, pressure)
		if sd > 0.0:
			_cycle_max_dp = maxf(_cycle_max_dp, (pressure - _cycle_p) / sd)
		_cycle_p = pressure

		phi = p1

	# Close cycle at 360°
	if _cycle_deg >= 300.0 and swept > 0.0:
		last_imep = _cycle_work / swept
		last_peak_pressure = _cycle_peak_p
		last_dp_dtheta = _cycle_max_dp
		last_ca10 = fposmod(_ca10, 360.0) if _ca10 >= 0.0 else -1.0
		last_ca50 = fposmod(_ca50, 360.0) if _ca50 >= 0.0 else -1.0
		last_ca90 = fposmod(_ca90, 360.0) if _ca90 >= 0.0 else -1.0
		last_burn_10_90 = _ca90 - _ca10 if _ca10 >= 0.0 and _ca90 >= _ca10 else 0.0
		_cycle_work = 0.0
		_cycle_deg = 0.0
		_cycle_peak_p = 0.0
		_cycle_max_dp = 0.0
		_cycle_p = 0.0
		_ca10 = -1.0
		_ca50 = -1.0
		_ca90 = -1.0

	return Vector2(work, fuel_consumed)


func _fuel_charge(tank: FuelTank, lambda: float, spark: bool, limiter_cut: bool, intake_p: float) -> void:
	var trapped := mass
	var fresh := maxf(trapped - _residual_kg, 0.0)
	last_fresh_kg = fresh
	last_ivc_temp = temp
	last_residual_fraction = _residual_kg / maxf(trapped, 1e-12)
	burn_energy = 0.0
	burn_energy_left = 0.0
	last_lambda = 1.0

	if limiter_cut or lambda >= MISFIRE_LAMBDA:
		return

	var wanted := fresh / (tank.afr * lambda)
	var supplied := minf(wanted, tank.mass_kg)
	tank.mass_kg -= supplied
	mass += supplied
	_u += supplied * CV * temp

	if not spark:
		fuel_unburnt_kg = supplied
		return

	fuel_unburnt_kg = 0.0
	if supplied > 0.0:
		last_lambda = fresh / (tank.afr * supplied)
	var burnable := minf(supplied, fresh / tank.afr)
	burn_energy = burnable * tank.lhv * COMBUSTION_EFFICIENCY
	burn_energy_left = burn_energy
	_burnt = 0.0
	_fired = supplied > 0.0


static func _in_burn_window(p: float, start: float) -> float:
	# 1 while the burn is under way: from the spark for the burn angle. (It used to subtract the same expression from itself, so the
	# burn never started and the engine made no torque.)
	var burn_deg := BURN_DEG_BASE + BURN_DEG_PER_RPM * 5000.0
	return 1.0 if fmod(p - start + 360.0, 360.0) < burn_deg else 0.0


static func _wiebe(rel: float) -> float:
	var burn_deg := BURN_DEG_BASE + BURN_DEG_PER_RPM * 5000.0
	return 1.0 - exp(-WIEBE_A * pow(clampf(rel / burn_deg, 0.0, 1.0), WIEBE_M + 1.0))


# Crank throw radius
var crank_radius := 0.0
func _init_crank_radius():
	crank_radius = stroke * 0.5


func _get_crank_radius() -> float:
	if crank_radius == 0.0:
		_init_crank_radius()
	return crank_radius