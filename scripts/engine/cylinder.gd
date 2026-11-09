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
const STEP_DEG := 10.0 # cylinder integration step, deg, coarse enough to run at 60 fps
const LIVE_HIGH_RPM_STEP_DEG := 20.0 # live four-cylinder fallback; offline rendering retains STEP_DEG
const LARGE_RUNNER_STEP_DEG := 1.0 # large-port filling needs this resolution; see R1M convergence audit
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
const OVERLAP_RETURN_BELOW := 0.9 # fraction of atmosphere: below this the overlap push stays in the port and is drawn back in
const AUTO_IGNITE_K := 900.0 # K, exhaust gas temperature above which unlit fuel leaving the cylinder can catch, estimate
const BACKFIRE_BURN := 0.5 # share of the unlit charge that burns in the hot exhaust when it catches, estimate
const EXHAUST_FLOW_BINS := 90

# Valve events of this cylinder's cams: crank degrees after firing top dead centre, and peak lift in metres.
# The stock constants above are the defaults; set_cams() takes them from the engine spec.
var intake_open := INTAKE_OPEN
var intake_close := INTAKE_CLOSE
var exhaust_open := EXHAUST_OPEN
var exhaust_close := EXHAUST_CLOSE
var intake_lift := INTAKE_LIFT
var exhaust_lift := EXHAUST_LIFT
var intake_valve_d := INTAKE_VALVE_D
var exhaust_valve_d := EXHAUST_VALVE_D
var runner_length := RUNNER_LENGTH
var runner_area := RUNNER_AREA
var wall_heat_scale := 1.0
var flow_step_deg := STEP_DEG

# Cam profile parameters (set by set_cams from EngineSpec)
var _intake_profile := 0
var _exhaust_profile := 0
var _intake_lift_curve: Array = []
var _exhaust_lift_curve: Array = []
var _intake_flat_frac := 0.3
var _exhaust_flat_frac := 0.3
var _intake_open_ramp := 0.0
var _intake_close_ramp := 0.0
var _exhaust_open_ramp := 0.0
var _exhaust_close_ramp := 0.0
var _intake_duration_050 := 0.0
var _exhaust_duration_050 := 0.0
var valve_cd := CD_VALVE

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
var exhaust_temp := 300.0 # K, the gas temperature when the exhaust valve last opened: the exhaust temperature sensor
var peak_temp := 300.0 # K, the hottest gas in the current cycle so far
var last_peak_temp := 300.0 # K, the hottest gas in the last complete cycle: the chamber temperature sensor reads it
var last_lambda := 1.0 # the mixture the O2 sensor reads, relative to stoichiometric: 1.0 is exact, above is lean
var _fired := false # true when this cycle's charge was lit, so its exhaust is hot
var fuel_unburnt_kg := 0.0 # kg of fuel injected into this charge but not lit: it leaves unburnt
var _port_heat := T0 # K, the exhaust port's heat from the last firing; an unlit charge can catch from it, and it is spent once used
var backfire_j := 0.0 # J released by backfires since the engine last read it
var _residual_kg := 0.0 # kg of burnt gas left in the cylinder when the exhaust valve closed
var _overlap_out := 0.0 # kg pushed back out the intake while the exhaust valve was still open; it is burnt gas, not fresh air
var _burnt := 0.0 # share of this cycle's fuel energy released so far, 0 = fresh air, 1 = all burnt
var wall_loss_j := 0.0 # J of heat lost to the walls since the cylinder was made
var _u := 0.0 # J, internal energy of the gas: the state that carries from step to step, temperature follows from it
var enthalpy_in_j := 0.0 # J of gas enthalpy brought in since the cylinder was made
var enthalpy_out_j := 0.0 # J of gas enthalpy carried out since the cylinder was made
var exhaust_mdot := 0.0 # kg/s into the pipe over the last advance, negative when the pipe flows back in
var exhaust_power := 0.0 # W of enthalpy into the pipe over the last advance
var _exhaust_flow_cycle := PackedFloat32Array()
var _cycle_work := 0.0 # J, ∮P dV since the last intake opening
var _cycle_deg := 0.0
var _cycle_peak_p := 0.0 # Pa
var _cycle_max_dp := 0.0 # Pa per crank degree
var _cycle_p := 0.0
var _ca10 := -1.0 # unwrapped crank angle where the burn fraction crossed the mark, or -1
var _ca50 := -1.0
var _ca90 := -1.0
var last_imep := 0.0 # Pa, net indicated, full four strokes of the last closed cycle
var last_peak_pressure := 0.0 # Pa
var last_dp_dtheta := 0.0 # Pa per crank degree, the steepest pressure rise of that cycle
var last_ca10 := -1.0 # crank degrees after firing top dead centre
var last_ca50 := -1.0
var last_ca90 := -1.0
var last_burn_10_90 := 0.0 # crank degrees from 10% to 90% burnt
var last_fresh_kg := 0.0 # air trapped at intake closing, residuals removed
var last_ivc_temp := T0 # K, charge temperature at intake closing
var last_residual_fraction := 0.0 # share of the trapped mass that is leftover exhaust


func setup(bore_mm: float, stroke_mm: float, compression_ratio: float, recip: float = 0.15, rod_lambda: float = 1.6) -> void:
	bore = bore_mm * 0.001
	piston_area = PI * bore * bore / 4.0
	stroke = stroke_mm * 0.001
	swept = piston_area * stroke
	recip_kg = recip
	rod_ratio = rod_lambda
	clearance = swept / (compression_ratio - 1.0)
	_cfg_dirty = true
	pressure = P0
	temp = T0
	mass = pressure * clearance / (R * temp)
	_u = mass * CV * temp
	phi = 0.0
	port_p = P0
	runner_q = 0.0
	_exhaust_flow_cycle.resize(EXHAUST_FLOW_BINS)
	_exhaust_flow_cycle.fill(0.0)


# Takes this cylinder's valve events and lifts from the engine spec.
func set_cams(spec: EngineSpec) -> void:
	intake_open = spec.intake_open_deg()
	intake_close = spec.intake_close_deg()
	exhaust_open = spec.exhaust_open_deg()
	exhaust_close = spec.exhaust_close_deg()
	intake_lift = spec.intake_lift_mm * 0.001
	exhaust_lift = spec.exhaust_lift_mm * 0.001
	intake_valve_d = spec.intake_valve_mm * 0.001
	exhaust_valve_d = spec.exhaust_valve_mm * 0.001
	runner_length = spec.runner_length_m
	runner_area = PI * pow(spec.runner_bore_mm * 0.001, 2) / 4.0 if spec.runner_bore_mm > 0.0 else RUNNER_AREA
	wall_heat_scale = spec.wall_heat_scale
	
	# Cam profile parameters
	var intake_profile := spec.intake_lobe_profile if spec.intake_lobe_profile >= 0 else spec.cam_lobe_profile
	var exhaust_profile := spec.exhaust_lobe_profile if spec.exhaust_lobe_profile >= 0 else spec.cam_lobe_profile
	_intake_profile = int(intake_profile)
	_exhaust_profile = int(exhaust_profile)
	_intake_lift_curve = spec.intake_lift_curve
	_exhaust_lift_curve = spec.exhaust_lift_curve
	_intake_flat_frac = spec.intake_flat_fraction
	_exhaust_flat_frac = spec.exhaust_flat_fraction
	_intake_open_ramp = spec.intake_open_ramp_deg
	_intake_close_ramp = spec.intake_close_ramp_deg
	_exhaust_open_ramp = spec.exhaust_open_ramp_deg
	_exhaust_close_ramp = spec.exhaust_close_ramp_deg
	_intake_duration_050 = spec.intake_duration_050_deg
	_exhaust_duration_050 = spec.exhaust_duration_050_deg
	valve_cd = spec.valve_cd
	_cfg_dirty = true


# Puts the piston at a phase with the gas at atmospheric pressure, so the start state matches the volume.
func start_at(phase_deg: float) -> void:
	phi = fposmod(phase_deg, 720.0)
	mass = pressure * volume(phi) / (R * temp)
	_u = mass * CV * temp


# Cylinder volume at phase phi, m³.
func volume(phi_deg: float) -> float:
	var angle := deg_to_rad(phi_deg)
	var crank_radius := stroke * 0.5
	var rod_length := rod_ratio * crank_radius
	var crank_offset := crank_radius * sin(angle)
	var displacement := crank_radius * (1.0 - cos(angle)) + rod_length - sqrt(rod_length * rod_length - crank_offset * crank_offset)
	return clearance + piston_area * displacement


const CHECK_LIFT_M := 0.00127 # 0.050 inch, the cam-card checking height
const SEAT_OVER_050 := 1.14 # the calculator's seat duration when the advertised figure is left blank


# Lift of one valve, metres, using the same lobe the cylinder breathes through.
static func valve_lift(spec: EngineSpec, intake: bool, phi_deg: float) -> float:
	var profile := spec.intake_lobe_profile if intake else spec.exhaust_lobe_profile
	if profile < 0:
		profile = spec.cam_lobe_profile
	if intake:
		return lobe_lift(phi_deg, spec.intake_open_deg(), spec.intake_close_deg(), spec.intake_lift_mm * 0.001,
				profile, spec.intake_lift_curve, spec.intake_open_ramp_deg, spec.intake_close_ramp_deg, spec.intake_duration_050_deg)
	return lobe_lift(phi_deg, spec.exhaust_open_deg(), spec.exhaust_close_deg(), spec.exhaust_lift_mm * 0.001,
			profile, spec.exhaust_lift_curve, spec.exhaust_open_ramp_deg, spec.exhaust_close_ramp_deg, spec.exhaust_duration_050_deg)


# Valve lift, metres. The cam-card lobe is the MGI calculator: a raised cosine between the 0.050 inch points
# and a straight ramp from there to the seat.
static func lobe_lift(phi_deg: float, open_deg: float, close_deg: float, peak_m: float,
		profile: int, curve: Array, open_ramp: float, close_ramp: float, duration_050: float) -> float:
	var p := fposmod(phi_deg, 720.0)
	if profile == EngineSpec.CamLobeProfile.CUSTOM:
		return _curve_lift(curve, p)
	if p < open_deg or p > close_deg or close_deg <= open_deg or peak_m <= 0.0:
		return 0.0
	var seat := close_deg - open_deg
	if profile == EngineSpec.CamLobeProfile.HALF_SINE:
		return peak_m * sin(PI * (p - open_deg) / seat)
	var ramps := EngineSpec.seat_ramps(seat, duration_050, open_ramp, close_ramp)
	var check_open := open_deg + ramps.x
	var check_close := close_deg - ramps.y
	var check_m := minf(CHECK_LIFT_M, peak_m * 0.5)
	if ramps.x > 0.05 and p < check_open:
		return check_m * (p - open_deg) / ramps.x
	if ramps.y > 0.05 and p > check_close:
		return check_m * (close_deg - p) / ramps.y
	var half := maxf((check_close - check_open) * 0.5, 0.5)
	var centre := (check_open + check_close) * 0.5
	var cos_arg := clampf(2.0 * check_m / peak_m - 1.0, -1.0, 1.0)
	var omega := acos(cos_arg) / half
	return peak_m * 0.5 * (cos(omega * (p - centre)) + 1.0)


static func _curve_lift(curve: Array, deg: float) -> float:
	if curve.size() < 2:
		return 0.0
	for i in range(curve.size() - 1):
		var d1 := float(curve[i][0])
		var d2 := float(curve[i + 1][0])
		if deg >= d1 and deg <= d2:
			var span := d2 - d1
			if span <= 0.0:
				return float(curve[i][1]) * 0.001
			var t := (deg - d1) / span
			return lerpf(float(curve[i][1]), float(curve[i + 1][1]), t) * 0.001
	return 0.0


func _lift(phi_deg: float, open_deg: float, close_deg: float, peak: float,
		profile: int, lift_curve: Array, _flat_frac: float,
		open_ramp_deg: float, close_ramp_deg: float, duration_050: float) -> float:
	return lobe_lift(phi_deg, open_deg, close_deg, peak, profile, lift_curve, open_ramp_deg, close_ramp_deg, duration_050)


# Exhaust valve curtain area at this crank phase, m² (two valves, capped by the port).
func exhaust_valve_area(phase_deg: float) -> float:
	var lift_m := _lift(phase_deg, exhaust_open, exhaust_close, exhaust_lift,
		_exhaust_profile, _exhaust_lift_curve, _exhaust_flat_frac,
		_exhaust_open_ramp, _exhaust_close_ramp, _exhaust_duration_050)
	return minf(2.0 * PI * exhaust_valve_d * lift_m, 0.5 * PI * exhaust_valve_d * exhaust_valve_d)


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


# Crank degrees per step stay coarse. A wide-open valve on a small chamber needs a shorter step than that:
# one long step can empty it, and the next step draws the exhaust back in. That reversal is a whistle.
func _flow_steps(dphi: float, dt: float, pm: float, tm: float, p_ex: float, t_ex: float) -> int:
	# Large runners lose their high-frequency filling pulse to numerical damping
	# at the legacy 10–20 degree limit; verified by the R1M timestep comparison.
	var max_deg := minf(flow_step_deg, LARGE_RUNNER_STEP_DEG) if runner_area > RUNNER_AREA else flow_step_deg
	var steps := maxi(1, maxi(ceili(absf(dphi) / max_deg), ceili(dt / MAX_FLOW_DT)))
	if dt <= 0.0 or mass < 1e-7:
		return steps
	var mid := phi + dphi * 0.5
	var end := phi + dphi
	var cd := valve_cd / CD_VALVE
	var ex_area := maxf(exhaust_valve_area(phi), maxf(exhaust_valve_area(mid), exhaust_valve_area(end))) * cd
	var in_area := maxf(_intake_area(phi), maxf(_intake_area(mid), _intake_area(end))) * cd
	var finer := steps
	var mdot := absf(mass_flow(ex_area, maxf(pressure, p_ex), maxf(temp, 250.0), minf(pressure, p_ex), t_ex))
	mdot = maxf(mdot, absf(mass_flow(in_area, maxf(port_p, pm), maxf(tm, 250.0), minf(pressure, pm), temp)))
	var cap := 0.1 * mass
	if mdot * dt > cap * float(finer):
		finer = maxi(finer, ceili(mdot * dt / cap))
	# Near equal pressure the orifice slope is steep, so a step sized on mass alone still reverses.
	var opening := maxf(ex_area, in_area)
	if opening > 0.0:
			var vol := mass * R * maxf(temp, 250.0) / maxf(pressure, 1000.0)
			var wave := sqrt(G * R * maxf(temp, 250.0))
			var dt_ok := 0.2 * vol / (opening * wave)
			if dt_ok > 0.0:
				finer = maxi(finer, ceili(dt / dt_ok))
	# The crank-angle step is never coarsened. The extra splits are capped so a small chamber cannot stall the frame.
	return mini(finer, maxi(steps, 24))


func _intake_area(phase_deg: float) -> float:
	var lift_m := _lift(phase_deg, intake_open, intake_close, intake_lift,
		_intake_profile, _intake_lift_curve, _intake_flat_frac,
		_intake_open_ramp, _intake_close_ramp, _intake_duration_050)
	return minf(2.0 * PI * intake_valve_d * lift_m, 0.5 * PI * intake_valve_d * intake_valve_d)


# Native path. The hot loop below (_advance_gd) is also written in C++ (gdextension/src/cylinder_kernel.cpp, class CylinderKernel).
# When that library is loaded, advance() hands the state to it as one array and reads the result back; if it is missing (an old
# app, a platform without the library) the GDScript loop runs instead. The two must agree: tests/unit/engine/cylinder_native_test.gd.
# The state order here is CylinderKernel::StateIndex; the config order is CylinderKernel::ConfigIndex.
static var native_available := ClassDB.class_exists("CylinderKernel")
static var _native_config_size: int = int(ClassDB.class_call_static("CylinderKernel", "config_size")) if native_available else 0
static var use_native := true # tests switch this to compare the two paths
const S_TANK_MASS := 43
const S_OUT_TORQUE := 44
const S_OUT_DRAWN := 45
const S_BINS := 48
var _st := PackedFloat64Array()
var _cfg := PackedFloat64Array()
var _icurve := PackedFloat64Array()
var _ecurve := PackedFloat64Array()
var _cfg_dirty := true
var _native_bins := false # the exhaust flow bins live in _st while the native path is in use


func _build_native_config() -> void:
	_cfg = PackedFloat64Array([bore, piston_area, stroke, swept, clearance, recip_kg, rod_ratio, intake_open, intake_close,
		exhaust_open, exhaust_close, intake_lift, exhaust_lift, intake_valve_d, exhaust_valve_d, runner_length, wall_heat_scale,
		valve_cd, float(_intake_profile), float(_exhaust_profile), _intake_open_ramp, _intake_close_ramp, _exhaust_open_ramp,
		_exhaust_close_ramp, _intake_duration_050, _exhaust_duration_050, runner_area])
	_icurve = _flatten_curve(_intake_lift_curve)
	_ecurve = _flatten_curve(_exhaust_lift_curve)
	_cfg_dirty = false


static func _flatten_curve(curve: Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for pair in curve:
		out.append(float(pair[0]))
		out.append(float(pair[1]))
	return out


func _advance_native(dphi: float, dt: float, pm: float, tm: float, ign_phi: float, firing: bool,
		tank: FuelTank, lambda: float, spark: bool, limiter_cut: bool, p_ex: float, t_ex: float) -> Vector2:
	if _cfg_dirty:
		_build_native_config()
	if _st.size() != 138:
		_st.resize(138)
	if not _native_bins: # first native call, or back from the GDScript path: the bins move into the state array
		for i in EXHAUST_FLOW_BINS:
			_st[S_BINS + i] = _exhaust_flow_cycle[i] if i < _exhaust_flow_cycle.size() else 0.0
		_native_bins = true
	_st[0] = phi
	_st[1] = mass
	_st[2] = temp
	_st[3] = pressure
	_st[4] = burn_energy_left
	_st[5] = burn_energy
	_st[6] = port_p
	_st[7] = runner_q
	_st[8] = exhaust_temp
	_st[9] = peak_temp
	_st[10] = last_peak_temp
	_st[11] = last_lambda
	_st[12] = 1.0 if _fired else 0.0
	_st[13] = fuel_unburnt_kg
	_st[14] = _port_heat
	_st[15] = backfire_j
	_st[16] = _residual_kg
	_st[17] = _overlap_out
	_st[18] = _burnt
	_st[19] = wall_loss_j
	_st[20] = _u
	_st[21] = enthalpy_in_j
	_st[22] = enthalpy_out_j
	_st[23] = exhaust_mdot
	_st[24] = exhaust_power
	_st[25] = _cycle_work
	_st[26] = _cycle_deg
	_st[27] = _cycle_peak_p
	_st[28] = _cycle_max_dp
	_st[29] = _cycle_p
	_st[30] = _ca10
	_st[31] = _ca50
	_st[32] = _ca90
	_st[33] = last_imep
	_st[34] = last_peak_pressure
	_st[35] = last_dp_dtheta
	_st[36] = last_ca10
	_st[37] = last_ca50
	_st[38] = last_ca90
	_st[39] = last_burn_10_90
	_st[40] = last_fresh_kg
	_st[41] = last_ivc_temp
	_st[42] = last_residual_fraction
	_st[S_TANK_MASS] = tank.mass_kg
	_st = CylinderKernel.advance(_st, _cfg, _icurve, _ecurve, dphi, dt, pm, tm, ign_phi, firing, tank.afr, tank.lhv, lambda,
		spark, limiter_cut, p_ex, t_ex, flow_step_deg)
	phi = _st[0]
	mass = _st[1]
	temp = _st[2]
	pressure = _st[3]
	burn_energy_left = _st[4]
	burn_energy = _st[5]
	port_p = _st[6]
	runner_q = _st[7]
	exhaust_temp = _st[8]
	peak_temp = _st[9]
	last_peak_temp = _st[10]
	last_lambda = _st[11]
	_fired = _st[12] != 0.0
	fuel_unburnt_kg = _st[13]
	_port_heat = _st[14]
	backfire_j = _st[15]
	_residual_kg = _st[16]
	_overlap_out = _st[17]
	_burnt = _st[18]
	wall_loss_j = _st[19]
	_u = _st[20]
	enthalpy_in_j = _st[21]
	enthalpy_out_j = _st[22]
	exhaust_mdot = _st[23]
	exhaust_power = _st[24]
	_cycle_work = _st[25]
	_cycle_deg = _st[26]
	_cycle_peak_p = _st[27]
	_cycle_max_dp = _st[28]
	_cycle_p = _st[29]
	_ca10 = _st[30]
	_ca50 = _st[31]
	_ca90 = _st[32]
	last_imep = _st[33]
	last_peak_pressure = _st[34]
	last_dp_dtheta = _st[35]
	last_ca10 = _st[36]
	last_ca50 = _st[37]
	last_ca90 = _st[38]
	last_burn_10_90 = _st[39]
	last_fresh_kg = _st[40]
	last_ivc_temp = _st[41]
	last_residual_fraction = _st[42]
	tank.mass_kg = _st[S_TANK_MASS]
	return Vector2(_st[S_OUT_TORQUE], _st[S_OUT_DRAWN])


func advance(dphi: float, dt: float, pm: float, tm: float, ign_phi: float, firing: bool,
		tank: FuelTank, lambda: float, spark: bool = true, limiter_cut: bool = false,
		p_ex: float = P0, t_ex: float = T0) -> Vector2:
	# Older app libraries ignore the appended runner area. Use the matching script
	# solver for non-legacy runners until that platform's native library is rebuilt.
	if native_available and use_native and (runner_area == RUNNER_AREA or _native_config_size >= 27):
		return _advance_native(dphi, dt, pm, tm, ign_phi, firing, tank, lambda, spark, limiter_cut, p_ex, t_ex)
	if _native_bins: # back from the native path: take the bins out of the state array
		for i in EXHAUST_FLOW_BINS:
			_exhaust_flow_cycle[i] = _st[S_BINS + i]
		_native_bins = false
	return _advance_gd(dphi, dt, pm, tm, ign_phi, firing, tank, lambda, spark, limiter_cut, p_ex, t_ex)


# Advances the cylinder by dphi degrees, taking dt seconds. pm and tm: manifold pressure and temperature.
# ign_phi: spark phase. firing: the engine is running. tank: fuel is drawn when the intake valve closes.
# limiter_cut: true when the rev limiter has cut spark for this cycle - if true, fuel is cut to prevent unburnt mixture.
# Returns Vector2(average gas torque over dphi in N·m, mass drawn from the manifold in kg).
func _advance_gd(dphi: float, dt: float, pm: float, tm: float, ign_phi: float, firing: bool,
		tank: FuelTank, lambda: float, spark: bool = true, limiter_cut: bool = false,
		p_ex: float = P0, t_ex: float = T0) -> Vector2:
	var steps := _flow_steps(dphi, dt, pm, tm, p_ex, t_ex)
	var sd := dphi / steps
	var sdt := dt / steps
	var work := 0.0
	var theta := 0.0
	var drawn := 0.0
	var w := deg_to_rad(dphi) / dt if dt > 0.0 else 0.0 # crank speed, rad/s
	var crank_r := stroke * 0.5
	var burn_deg := burn_duration_deg(w * 60.0 / TAU)
	var h_wall := WALL_HEAT * wall_heat_scale * pow(maxf(w, 1.0) / WALL_REF_W, 0.8)
	var previous_volume := volume(phi)
	var ex_mass := 0.0
	var ex_energy := 0.0
	for i in steps:
		var p0 := phi
		var p1 := phi + sd
		var next_volume := volume(p1)
		var dv := next_volume - previous_volume
		if _crossed(p0, p1, intake_open):
			_close_cycle()
			last_peak_temp = peak_temp # the cycle just ended: its hottest gas
			peak_temp = temp
			_burnt = 0.0 # a new cycle starts with fresh air

		# runner and port, solved together for their new values: the air column and the port form a resonator (about 400 Hz on this
		# engine) that an explicit step drives unstable at the finer steps. The implicit solve is stable at any step length.
		var v_run := runner_q / (runner_area * 1.2)
		var drag := 0.5 * RUNNER_LOSS * 1.2 * v_run * absf(v_run) # lagged from the last step
		var m_in := mass_flow(minf(2.0 * PI * intake_valve_d * _lift(p0, intake_open, intake_close, intake_lift,
			_intake_profile, _intake_lift_curve, _intake_flat_frac,
			_intake_open_ramp, _intake_close_ramp, _intake_duration_050), 0.5 * PI * intake_valve_d * intake_valve_d) * valve_cd / CD_VALVE, port_p, tm, pressure, temp) * sdt
		var exhaust_lift_now := _lift(p0, exhaust_open, exhaust_close, exhaust_lift,
				_exhaust_profile, _exhaust_lift_curve, _exhaust_flat_frac,
				_exhaust_open_ramp, _exhaust_close_ramp, _exhaust_duration_050)
		# overlap: gas leaving the cylinder through the intake is burnt gas from this cycle, and the intake stroke draws it back in
		if m_in < 0.0 and exhaust_lift_now > 0.0:
			_overlap_out -= m_in
		var air_a := runner_area / runner_length * sdt
		var port_c := R * tm / PORT_VOLUME
		var k := port_c * air_a * sdt
		var dp := (port_c * sdt * runner_q + k * (pm - port_p - drag) - port_c * m_in) / (1.0 + k)
		runner_q += air_a * (pm - port_p - drag - dp)
		port_p = clampf(port_p + dp, 1000.0, 3.0 * P0)
		var m_out := mass_flow(minf(2.0 * PI * exhaust_valve_d * exhaust_lift_now, 0.5 * PI * exhaust_valve_d * exhaust_valve_d) * valve_cd / CD_VALVE, pressure, temp, p_ex, t_ex) * sdt
		if sdt > 0.0:
			var first_bin := floori(p0 * EXHAUST_FLOW_BINS / 720.0)
			var last_bin := floori(p1 * EXHAUST_FLOW_BINS / 720.0)
			for bin_index in range(first_bin, last_bin + 1):
				_exhaust_flow_cycle[posmod(bin_index, EXHAUST_FLOW_BINS)] = m_out / sdt

		# exhaust valve closes: what is left in the cylinder is burnt gas from the last cycle, not fresh air
		if _crossed(p0, p1, exhaust_open):
			# unlit fuel leaving into hot exhaust catches and pops; the exhaust sensor holds the heat of the last fired cycle
			if fuel_unburnt_kg > 0.0:
				if _port_heat > AUTO_IGNITE_K:
					backfire_j += fuel_unburnt_kg * tank.lhv * BACKFIRE_BURN
				_port_heat = T0 # the heat of the last firing is spent on this charge, so one unlit charge pops per firing
			fuel_unburnt_kg = 0.0
		if _fired and _crossed(p0, p1, exhaust_open):
			exhaust_temp = temp # the exhaust temperature sensor reads burnt gas as the exhaust valve opens, held through a limiter cut
			_port_heat = temp # the exhaust port is hot from a firing: this is what an unlit charge can catch from
		if _crossed(p0, p1, exhaust_close):
			_residual_kg = mass

		# intake valve closes: the fresh air that came in sets how much fuel is injected and burned
		if _crossed(p0, p1, intake_close):
			_fired = false
			if firing:
				_fuel_charge(tank, lambda, spark, limiter_cut, pm)
			else:
				_overlap_out = 0.0

		# combustion heat, released over the burn duration starting at the spark
		var dq := 0.0
		if spark and burn_energy_left > 0.0 and _in_window(p0, ign_phi, burn_deg):
			var rel := fmod(p0 - ign_phi + 720.0, 720.0)
			dq = minf(burn_energy_left, burn_energy * (_wiebe(rel + sd, burn_deg) - _wiebe(rel, burn_deg)))
			burn_energy_left -= dq
			_burnt = 1.0 - burn_energy_left / burn_energy

		# heat lost to the walls: head plus piston crown plus the liner exposed by the piston
		var liner := (next_volume - clearance) / piston_area
		var wall_area := 2.0 * piston_area + PI * bore * maxf(liner, 0.0)
		# wall heat transfer grows with gas motion (Woschni-like, speed^0.8), so it is small when cranking
		var q_loss := h_wall * wall_area * (temp - WALL_TEMP) * sdt
		wall_loss_j += q_loss # running total, for the combustion checks

		# first law for the gas in the cylinder
		# the heat capacity moves from air to combustion products as the charge burns (CV_BURNT once it is all burnt)
		var cv := CV + _burnt * (CV_BURNT - CV)
		var cp := cv + R
		var h_in := cp * (tm if m_in >= 0.0 else temp) * m_in
		enthalpy_in_j += h_in # running totals, for the energy balance check
		var h_ex := cp * (temp if m_out >= 0.0 else t_ex) * m_out
		enthalpy_out_j += h_ex
		ex_mass += m_out
		ex_energy += h_ex
		var old_pressure := pressure
		# Use the same trapezoidal P*dV work in the energy equation and shaft
		# output. Solve the ideal-gas endpoint pressure implicitly.
		var source_energy := _u + dq + h_in - h_ex - q_loss
		var u := (source_energy - 0.5 * old_pressure * dv) / (1.0 + 0.5 * R / cv * dv / next_volume)
		mass = maxf(mass + m_in - m_out, 1e-12)
		# guard: a single step must never push the gas outside physical limits
		temp = clampf(u / (mass * cv), 200.0, 4000.0)
		_u = mass * cv * temp
		peak_temp = maxf(peak_temp, temp) # the hottest gas this cycle: the chamber temperature sensor
		pressure = clampf(mass * R * temp / next_volume, 1000.0, 1.0e7)
		if sd > 0.0 and _cycle_deg > 0.0:
			_cycle_max_dp = maxf(_cycle_max_dp, (pressure - _cycle_p) / sd)
		_cycle_p = pressure
		_cycle_peak_p = maxf(_cycle_peak_p, pressure)
		var boundary_work := 0.5 * (old_pressure + pressure) * dv
		_cycle_work += boundary_work
		_cycle_deg += sd
		if _ca10 < 0.0 and _burnt >= 0.1:
			_ca10 = p1
		if _ca50 < 0.0 and _burnt >= 0.5:
			_ca50 = p1
		if _ca90 < 0.0 and _burnt >= 0.9:
			_ca90 = p1

		var dtheta := sd * PI / 180.0
		work += boundary_work - P0 * dv
		# inertia of the moving piston and rod: a = r·ω²·(cos φ + cos 2φ / λ), torque = -m·a·r·sin φ
		var phi_r := deg_to_rad(p0)
		var accel_term := cos(phi_r) + cos(2.0 * phi_r) / rod_ratio
		work += -recip_kg * crank_r * crank_r * w * w * accel_term * sin(phi_r) * dtheta
		theta += dtheta
		drawn += runner_q * sdt
		phi = p1
		previous_volume = next_volume
	exhaust_mdot = ex_mass / dt if dt > 0.0 else 0.0
	exhaust_power = ex_energy / dt if dt > 0.0 else 0.0
	return Vector2(work / theta if theta > 0.0 else 0.0, drawn)


func exhaust_flow_at(phase_deg: float) -> float:
	if _exhaust_flow_cycle.is_empty():
		return 0.0
	var position := fposmod(phase_deg, 720.0) * EXHAUST_FLOW_BINS / 720.0
	var index := floori(position)
	if _native_bins:
		return lerpf(_st[S_BINS + index], _st[S_BINS + (index + 1) % EXHAUST_FLOW_BINS], position - index)
	return lerpf(_exhaust_flow_cycle[index], _exhaust_flow_cycle[(index + 1) % EXHAUST_FLOW_BINS], position - index)


func _fuel_charge(tank: FuelTank, lambda: float, spark: bool, limiter_cut: bool = false, pm: float = P0) -> void:
	var trapped := mass
	# In vacuum the overlap push sits in the port and the intake stroke draws that burnt gas back in, so it is
	# not air. Wide open, the runner is flushing fresh air and this trapped mass is the air the power figures use.
	var came_back := 0.0
	if pm < P0 * OVERLAP_RETURN_BELOW:
		came_back = minf(_overlap_out, maxf(trapped - _residual_kg, 0.0))
	_overlap_out = 0.0
	last_fresh_kg = maxf(trapped - _residual_kg - came_back, 0.0)
	last_ivc_temp = temp
	last_residual_fraction = (_residual_kg + came_back) / maxf(trapped, 1.0e-12)
	burn_energy = 0.0
	burn_energy_left = 0.0
	last_lambda = 1.0 # neutral when cycle is cut or not fired
	# Limiter cut: fuel cut to prevent unburnt mixture in exhaust
	if limiter_cut:
		return
	if lambda >= MISFIRE_LAMBDA:
		return # too lean to light
	var fresh := last_fresh_kg # the burnt gas left from the last cycle, including what overlap pushed into the port, takes no fuel
	var wanted := fresh / (tank.afr * lambda)
	var supplied := minf(wanted, tank.mass_kg)
	tank.mass_kg -= supplied
	mass += supplied # the fuel joins the charge, so the gas carries the mass it releases energy from
	_u += supplied * CV * temp # at the gas temperature, so the mix stays at the same temperature
	if not spark:
		fuel_unburnt_kg = supplied # injected but not lit: it stays unburnt and leaves with the exhaust
		return
	fuel_unburnt_kg = 0.0
	if supplied > 0.0:
		last_lambda = fresh / (tank.afr * supplied) # the air-fuel ratio actually burned, relative to stoichiometric: what the O2 sensor sees
	# only the fuel the air can burn releases energy: in a rich mixture the excess passes through unburnt and cools the exhaust
	var burnable := minf(supplied, fresh / tank.afr)
	burn_energy = burnable * tank.lhv * COMBUSTION_EFFICIENCY
	burn_energy_left = burn_energy
	_fired = supplied > 0.0


# Crank degrees from spark to the end of the burn at this speed. Shared with the spark timing in EngineAir.
static func burn_duration_deg(rpm: float) -> float:
	return BURN_DEG_BASE + BURN_DEG_PER_RPM * rpm


# Fraction of the charge burnt at this many degrees after the spark.
static func _wiebe(rel: float, burn_deg: float) -> float:
	return 1.0 - exp(-WIEBE_A * pow(clampf(rel / burn_deg, 0.0, 1.0), WIEBE_M + 1.0))


# Stores the closed cycle. A short first pass, before the crank has been round once, is discarded.
func _close_cycle() -> void:
	if _cycle_deg >= 400.0 and swept > 0.0:
		last_imep = _cycle_work / swept
		last_peak_pressure = _cycle_peak_p
		last_dp_dtheta = _cycle_max_dp
		last_ca10 = fposmod(_ca10, 720.0) if _ca10 >= 0.0 else -1.0
		last_ca50 = fposmod(_ca50, 720.0) if _ca50 >= 0.0 else -1.0
		last_ca90 = fposmod(_ca90, 720.0) if _ca90 >= 0.0 else -1.0
		last_burn_10_90 = _ca90 - _ca10 if _ca10 >= 0.0 and _ca90 >= _ca10 else 0.0
	_cycle_work = 0.0
	_cycle_deg = 0.0
	_cycle_peak_p = 0.0
	_cycle_max_dp = 0.0
	_ca10 = -1.0
	_ca50 = -1.0
	_ca90 = -1.0


static func _crossed(a: float, b: float, at: float) -> bool:
	return floor((b - at) / 720.0) > floor((a - at) / 720.0)


static func _in_window(p: float, start: float, length: float) -> bool:
	var rel := fmod(p - start + 720.0, 720.0)
	return rel < length
