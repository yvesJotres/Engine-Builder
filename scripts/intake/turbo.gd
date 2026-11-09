class_name Turbo
extends RefCounted

# Turbo and compressor model: the compressor map, shaft speed, the exhaust-driven turbine, the wastegate and the electric
# motor. It works on the intake state held by EngineAir (its compressor_* fields and surge/choke counts), so callers see the
# same fields as before.

const FLOW_AVG_TIME := 0.03 # s: the turbo sees the air flow averaged over a few cylinder events, not each pulse
const EXH_RATIO := 1.15 # exhaust pressure upstream of the turbine over the manifold pressure (never below ambient)
const START_OMEGA := 100.0 # rad/s: the speed a turbine starts from at rest, about 1000 rpm
const CP_AIR := 1005.0 # J/(kg·K)
const BASE_SPEED_RPM := 50000.0 # electric motor: constant torque up to here, then constant power


# Advances the compressor map model in air by dt seconds, given the engine's air draw m_dot_engine (kg/s).
static func update_map(air: EngineAir, dt: float, spec: EngineSpec, m_dot_engine: float, throttle: float, engine_running: bool) -> void:
	if air.compressor_map == null:
		return

	# Inlet conditions (pre-compressor)
	var T_in: float = EngineAir.T0
	var P_in: float = EngineAir.P0

	# Corrected flow from engine demand
	air._flow_avg += (m_dot_engine - air._flow_avg) * (1.0 - exp(-dt / FLOW_AVG_TIME))
	var m_flow: float = air._flow_avg
	var corr_flow = air.compressor_map.correct_flow(m_flow, T_in, P_in)

	# Current corrected speed
	var corr_speed = air.compressor_map.correct_speed(air.compressor_speed_rpm, T_in)

	# Map lookup
	var map_res = air.compressor_map.lookup(corr_speed, corr_flow)
	var target_pr: float = map_res.pr
	# the map starts at its lowest speed line; a wheel slower than that makes proportionally less pressure, none at rest
	target_pr = 1.0 + (target_pr - 1.0) * clampf(corr_speed / air.compressor_map.speed_lines[0][0], 0.0, 1.0)
	var comp_eff: float = map_res.eff

	# Compressor power required [W]
	var gamma := EngineAir.GAMMA
	var Cp := CP_AIR
	var T_out_ideal := T_in * pow(target_pr, (gamma - 1.0) / gamma)
	var T_out_actual := T_in + (T_out_ideal - T_in) / comp_eff
	var P_comp := m_flow * Cp * (T_out_actual - T_in)

	# Turbine / motor power available
	var P_turbine: float = 0.0
	if spec.electric_compressor:
		# Electric motor limited by battery & power rating
		var batt_frac: float = air.compressor_charge
		P_turbine = spec.compressor_power_w * batt_frac
		var charging: float = maxf(spec.compressor_charge_w, 0.0) if engine_running else 0.0
		var battery_wh: float = maxf(spec.compressor_battery_wh, 0.1)
		air.compressor_charge = clampf(air.compressor_charge + (charging - P_turbine) * dt / (battery_wh * 3600.0), 0.0, 1.0)
	else:
		# Exhaust turbine: energy from exhaust flow
		# Simplified: turbine power ~ mass_flow * Cp * T * (1 - PR^(-(γ-1)/γ)) * eff
		# We need exhaust temp and pressure - estimate from engine conditions
		var exh_mass_flow: float = m_flow * (1.0 + 1.0 / 14.7) # approx with fuel at stoich
		var exh_T: float = 900.0 # K, estimated exhaust temp
		var exh_P: float = maxf(air.pressure, EngineAir.P0) * EXH_RATIO # shortcut: exhaust pressure from the manifold, not the exhaust flow; the pipe solver would give the real value
		var turbine_pr: float = exh_P / P_in
		if turbine_pr > 1.0:
			P_turbine = exh_mass_flow * Cp * exh_T * (1.0 - pow(turbine_pr, -(gamma - 1.0) / gamma)) * spec.turbine_efficiency
		# Wastegate
		if spec.wastegate_type != "none" and target_pr > spec.wastegate_pressure_ratio:
			# the surplus exhaust bypasses the turbine: it keeps only the power that holds the wastegate pressure, so the shaft keeps its speed
			var wg_power: float = m_flow * Cp * T_in * (pow(spec.wastegate_pressure_ratio, (gamma - 1.0) / gamma) - 1.0) / comp_eff
			P_turbine = minf(P_turbine, wg_power)

	# Shaft acceleration
	var P_net: float = P_turbine - P_comp
	# Motor torque model: constant torque up to base speed, then constant power
	if spec.compressor_inertia_kgm2 > 0.0:
		if air.compressor_speed_rpm > 0.0:
			# Power = torque * omega, so torque = P / omega
			var omega: float = air.compressor_speed_rpm * TAU / 60.0
			var torque: float = P_net / maxf(omega, 1.0)
			var accel: float = torque / spec.compressor_inertia_kgm2
			air.compressor_speed_rpm += accel * dt * 60.0 / TAU
		elif P_net > 0.0:
			# At zero speed: use stall torque = rated_power / base_omega
			var base_omega: float = BASE_SPEED_RPM * TAU / 60.0
			var stall_torque: float = spec.compressor_power_w / base_omega
			if not spec.electric_compressor:
				# a turbo has no motor: its own spare exhaust power starts it from rest
				stall_torque = P_net / START_OMEGA
			var accel: float = stall_torque / spec.compressor_inertia_kgm2
			air.compressor_speed_rpm += accel * dt * 60.0 / TAU
	air.compressor_speed_rpm = maxf(0.0, air.compressor_speed_rpm)

	# Apply throttle modulation to PR (throttle downstream of compressor)
	air.compressor_pr = 1.0 + (target_pr - 1.0) * throttle
	air.compressor_eff = comp_eff

	# Surge/choke detection
	if air.compressor_map.is_surge(corr_flow, target_pr):
		air.surge_count += 1
		air.compressor_pr *= 0.95 # pressure collapse
	if air.compressor_map.is_choke(corr_flow, target_pr):
		air.choke_count += 1
		# Flow limited, PR naturally limited by choke
