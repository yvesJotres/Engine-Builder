class_name EngineAir
extends RefCounted

# Intake manifold: the throttle plate and idle bypass feed one lumped pressure, which the cylinders draw from.
# The cylinders themselves, with their valves, fuel and burn, are in Cylinder.

const P0 := 101325.0 # atmosphere, Pa
const T0 := 300.0 # intake air temperature, K
const R_AIR := 287.0 # J/(kg·K)
const GAMMA := 1.4
const CD := 0.8 # discharge coefficient for plate and bypass orifices
const THROTTLE_BORE_MM := 30.0 # placeholder, not verified for the CBR150R, drawing uses the same value
const THROTTLE_AREA := PI * 0.015 * 0.015 # from THROTTLE_BORE_MM
const BYPASS_AREA := PI * 0.00087 * 0.00087 # idle bypass radius, 0.87 mm: about 0.45 g/s of idle air for a 150 cc engine (a rough physical estimate)
const MANIFOLD_VOLUME := 5e-4 # m³, manifold plus airbox
const MIN_PRESSURE := 5000.0 # Pa, a floor so the vacuum stays finite
# Ram-air: pressure recovery from dynamic pressure at speed. Typical recovery 0.1 to 0.3 for sport bike airboxes.
const RAM_AIR_RECOVERY := 0.15 # fraction of dynamic pressure recovered (0.15 = 15% efficient airbox)
# Compressor constants
const CP_AIR := 1005.0 # J/(kg·K)

var pressure := P0 # intake manifold pressure, Pa
var bypass_area := BYPASS_AREA # idle bypass for this engine, m²; the simulator scales it with displacement
var limiter_cut := false # true while the rev limiter has the spark cut, set by EngineSim
var boost_ratio := 1.0
var compressor_charge := 1.0
var compressor_load := 0.0
var ram_air_boost := 1.0 # multiplicative boost from ram-air (speed dependent)

# Compressor map model
var compressor_map: CompressorMap = null
var compressor_speed_rpm: float = 0.0
var compressor_pr: float = 1.0
var compressor_eff: float = 0.7
var surge_count: int = 0
var choke_count: int = 0


# Spark advance before top dead centre, degrees: the advance that puts the burn centre (50% burnt) at CA50_TARGET degrees
# after TDC, which is where torque is best. It follows our own burn duration, so the burn centre stays put at every speed.
# (engine-sim's speed-only timing map was tried and dropped: it was tuned for that simulator's much slower burn at high
# speed, and in our burn model it pulls the burn centre to 40 degrees before TDC at 15,000 rpm.) The ECU adds its idle trim.
static func spark_advance_deg(rpm: float, offset := 0.0) -> float: # offset: the rider's advance (+) or retard (-), degrees
	return Cylinder.burn_duration_deg(rpm) * Cylinder.WIEBE_CA50 - Cylinder.CA50_TARGET + offset


# Returns target lambda for given throttle (0-1) and RPM, using the spec's lambda_target map.
static func get_target_lambda(spec: EngineSpec, throttle: float, rpm: float) -> float:
	return spec.get_target_lambda(throttle, rpm)


func setup(spec: EngineSpec) -> void:
	if spec.compressor_map_id != "":
		compressor_map = CompressorMap.load_from_json("res://assets/compressor_maps/" + spec.compressor_map_id + ".json")
		compressor_speed_rpm = 0.0
		compressor_pr = 1.0
		compressor_eff = 0.7
		surge_count = 0
		choke_count = 0


# Moves the manifold for dt seconds: throttle and bypass inflow, drawn_kg_s out to the cylinders.
func manifold_update(dt: float, throttle: float, drawn_kg_s: float, spec: EngineSpec = null, rpm: float = 0.0, engine_running: bool = true, bike_speed_ms: float = 0.0) -> void:
	# Apply VE scale to drawn air mass (cylinder intake) to match real volumetric efficiency; 1.0 when no spec is given
	var drawn_scaled := drawn_kg_s * (spec.ve_scale if spec != null else 1.0)
	var target_boost := 1.0
	var volume_scale := 1.0
	var area_scale := 1.0
	var supply_pressure := P0
	
	if spec != null:
		var speed_factor := clampf((rpm - 1500.0) / 3500.0, 0.0, 1.0)
		compressor_load = 0.0
		
		if spec.electric_compressor or spec.compressor_map_id != "":
			# Map-based compressor model
			_update_compressor_map(dt, spec, drawn_scaled, throttle, engine_running, rpm)
			target_boost = compressor_pr
			speed_factor = 1.0 # map handles speed dependence
		else:
			# Legacy electric compressor model
			var available := clampf(compressor_charge / 0.1, 0.0, 1.0)
			compressor_load = clampf(throttle, 0.0, 1.0) * available if engine_running else 0.0
			speed_factor = available if engine_running else 0.0
			var draw := compressor_load * maxf(spec.compressor_power_w, 0.0)
			var charging := maxf(spec.compressor_charge_w, 0.0) if engine_running else 0.0
			compressor_charge = clampf(compressor_charge + (charging - draw) * dt / (maxf(spec.compressor_battery_wh, 0.1) * 3600.0), 0.0, 1.0)
		
		if spec.compressor_map_id == "" and not spec.electric_compressor:
			# Legacy boost spool for non-map turbos
			target_boost += maxf(spec.max_boost_ratio - 1.0, 0.0) * speed_factor * clampf(throttle, 0.0, 1.0)
			boost_ratio += (target_boost - boost_ratio) * (1.0 - exp(-dt / maxf(spec.boost_spool_time, 0.01)))
		else:
			boost_ratio = target_boost
		
		volume_scale = maxf(spec.manifold_volume_scale, 0.01)
		area_scale = maxf(spec.intake_area_scale, 0.01)
	else:
		boost_ratio = 1.0
	
	# Ram-air: dynamic pressure recovery at speed. 0.5 * rho * v^2 * recovery_factor
	if spec != null and bike_speed_ms > 0.0:
		var dynamic_pressure := 0.5 * 1.2 * bike_speed_ms * bike_speed_ms # rho * v^2 / 2
		ram_air_boost = 1.0 + (dynamic_pressure * RAM_AIR_RECOVERY / P0)
	else:
		ram_air_boost = 1.0
	
	supply_pressure = P0 * boost_ratio * ram_air_boost
	var plate_area := THROTTLE_AREA * area_scale * (1.0 - cos(throttle * PI / 2.0))
	var inflow := _orifice(plate_area, supply_pressure) + _orifice(bypass_area, supply_pressure)
	pressure = clampf(pressure + R_AIR * T0 / (MANIFOLD_VOLUME * volume_scale) * (inflow - drawn_scaled) * dt, MIN_PRESSURE, supply_pressure)


func _update_compressor_map(dt: float, spec: EngineSpec, m_dot_engine: float, throttle: float, engine_running: bool, rpm: float) -> void:
	if compressor_map == null:
		return
	
	# Inlet conditions (pre-compressor)
	var T_in = T0
	var P_in = P0
	
	# Corrected flow from engine demand
	var corr_flow = compressor_map.correct_flow(m_dot_engine, T_in, P_in)
	
	# Current corrected speed
	var corr_speed = compressor_map.correct_speed(compressor_speed_rpm, T_in)
	
	# Map lookup
	var map_res = compressor_map.lookup(corr_speed, corr_flow)
	var target_pr = map_res.pr
	var comp_eff = map_res.eff
	
	# Compressor power required [W]
	var gamma = GAMMA
	var Cp = CP_AIR
	var T_out_ideal = T_in * pow(target_pr, (gamma - 1.0) / gamma)
	var T_out_actual = T_in + (T_out_ideal - T_in) / comp_eff
	var P_comp = m_dot_engine * Cp * (T_out_actual - T_in)
	
	# Turbine / motor power available
	var P_turbine: float = 0.0
	if spec.electric_compressor:
		# Electric motor limited by battery & power rating
		var batt_frac: float = compressor_charge
		P_turbine = spec.compressor_power_w * batt_frac
		var draw: float = P_turbine * dt
		var charging: float = maxf(spec.compressor_charge_w, 0.0) if engine_running else 0.0
		var battery_wh: float = maxf(spec.compressor_battery_wh, 0.1)
		compressor_charge = clampf(compressor_charge + (charging - P_turbine) * dt / (battery_wh * 3600.0), 0.0, 1.0)
	else:
		# Exhaust turbine: energy from exhaust flow
		# Simplified: turbine power ~ mass_flow * Cp * T * (1 - PR^(-(γ-1)/γ)) * eff
		# We need exhaust temp and pressure - estimate from engine conditions
		var exh_mass_flow: float = m_dot_engine * (1.0 + 1.0 / 14.7) # approx with fuel at stoich
		var exh_T: float = 900.0 # K, estimated exhaust temp
		var exh_P: float = pressure * target_pr * 0.8 # rough estimate
		var turbine_pr: float = exh_P / P_in
		if turbine_pr > 1.0:
			P_turbine = exh_mass_flow * Cp * exh_T * (1.0 - pow(turbine_pr, -(gamma - 1.0) / gamma)) * spec.turbine_efficiency
		# Wastegate
		if spec.wastegate_type != "none" and target_pr > spec.wastegate_pressure_ratio:
			P_turbine *= 0.5 # bypass half
	
	# Shaft acceleration
	var P_net: float = P_turbine - P_comp
	if P_net != 0.0 and spec.compressor_inertia_kgm2 > 0.0 and compressor_speed_rpm > 0.0:
		var accel: float = P_net / (spec.compressor_inertia_kgm2 * compressor_speed_rpm * TAU / 60.0) # rad/s²
		compressor_speed_rpm += accel * dt * 60.0 / TAU
	elif P_net > 0.0 and spec.compressor_inertia_kgm2 > 0.0:
		# Starting from zero speed
		var accel: float = P_net / spec.compressor_inertia_kgm2
		compressor_speed_rpm += accel * dt * 60.0 / TAU
	compressor_speed_rpm = maxf(0.0, compressor_speed_rpm)
	
	# Apply throttle modulation to PR (throttle downstream of compressor)
	compressor_pr = 1.0 + (target_pr - 1.0) * throttle
	compressor_eff = comp_eff
	
	# Surge/choke detection
	if compressor_map.is_surge(corr_flow, target_pr):
		surge_count += 1
		compressor_pr *= 0.95 # pressure collapse
	if compressor_map.is_choke(corr_flow, target_pr):
		choke_count += 1
		# Flow limited, PR naturally limited by choke


# Compressible mass flow through an orifice from atmosphere into the manifold, kg/s.
func _orifice(area: float, upstream_pressure: float = P0) -> float:
	var pr := pressure / upstream_pressure
	if pr >= 1.0 or area <= 0.0:
		return 0.0
	var k := CD * area * upstream_pressure / sqrt(R_AIR * T0)
	var critical := pow(2.0 / (GAMMA + 1.0), GAMMA / (GAMMA - 1.0))
	if pr <= critical:
		return k * sqrt(GAMMA * pow(2.0 / (GAMMA + 1.0), (GAMMA + 1.0) / (GAMMA - 1.0)))
	return k * sqrt(2.0 * GAMMA / (GAMMA - 1.0) * (pow(pr, 2.0 / GAMMA) - pow(pr, (GAMMA + 1.0) / GAMMA)))