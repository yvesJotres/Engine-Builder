class_name EngineMetrics
extends RefCounted

# Read-only figures from the simulator: efficiencies, power, emissions, combustion timing. Moved out of EngineSim;
# each function takes the sim first. EngineSim keeps the same names as wrappers.

# Exhaust gas temperature sensor, °C: the average of the cylinders' exhaust gas as their exhaust valves open.
static func exhaust_temp_c(sim: EngineSim) -> float:
	if sim.cylinders.is_empty():
		return 0.0
	var sum := 0.0
	for c in sim.cylinders:
		sum += c.exhaust_temp
	return sum / sim.cylinders.size() - 273.15


# Chamber temperature sensor, °C: the hottest gas each cylinder reached in its last complete cycle, averaged over the cylinders.
static func chamber_peak_c(sim: EngineSim) -> float:
	if sim.cylinders.is_empty():
		return 0.0
	var sum := 0.0
	for c in sim.cylinders:
		sum += c.last_peak_temp
	return sum / sim.cylinders.size() - 273.15


# Exhaust port temperatures, °C, one per cylinder: the gas each one last sent out (what each header runner carries).
static func port_temps_c(sim: EngineSim) -> Array:
	var out := []
	for c in sim.cylinders:
		out.append(c.exhaust_temp - 273.15)
	return out


# O2 sensor, relative to stoichiometric: the average mixture the cylinders burned on their last cycle. 1.0 is exact.
static func o2_lambda(sim: EngineSim) -> float:
	if sim.cylinders.is_empty():
		return 0.0
	var sum := 0.0
	var n := 0
	for c in sim.cylinders:
		if c.last_lambda < 50.0:
			sum += c.last_lambda
			n += 1
	return sum / n if n > 0 else 99.0


static func swept_m3(sim: EngineSim) -> float:
	var volume := 0.0
	for c in sim.cylinders:
		volume += c.swept
	return volume


# Net indicated mean effective pressure, Pa: the closed-cycle ∮P dV divided by swept volume, averaged over the cylinders.
static func imep_pa(sim: EngineSim) -> float:
	var sum := 0.0
	var n := 0
	for c in sim.cylinders:
		if c.last_imep != 0.0:
			sum += c.last_imep
			n += 1
	return sum / n if n > 0 else 0.0


# Brake mean effective pressure, Pa, from the mean shaft torque of the last closed cycle.
static func bmep_pa(sim: EngineSim) -> float:
	var volume := EngineMetrics.swept_m3(sim)
	if volume <= 0.0:
		return 0.0
	var shaft := sim.cycle_brake_torque if sim.cycle_brake_torque != 0.0 else sim.torque
	return shaft * 4.0 * PI / volume


# Friction mean effective pressure, Pa: what the net indicated pressure loses before it reaches the shaft.
static func fmep_pa(sim: EngineSim) -> float:
	return EngineMetrics.imep_pa(sim) - EngineMetrics.bmep_pa(sim)


static func indicated_power_w(sim: EngineSim) -> float:
	if sim.rpm <= 0.0:
		return 0.0
	return EngineMetrics.imep_pa(sim) * EngineMetrics.swept_m3(sim) * sim.rpm / 120.0


static func brake_power_w(sim: EngineSim) -> float:
	var shaft := sim.cycle_brake_torque if sim.cycle_brake_torque != 0.0 else sim.torque
	return Units.power_w(shaft, sim.rpm)


# g/kWh. Zero when the shaft is not delivering power.
static func bsfc_g_kwh(sim: EngineSim) -> float:
	var power_kw := EngineMetrics.brake_power_w(sim) / 1000.0
	if power_kw <= 0.05:
		return 0.0
	return sim.fuel_flow * 3600.0 / power_kw


static func isfc_g_kwh(sim: EngineSim) -> float:
	var power_kw := EngineMetrics.indicated_power_w(sim) / 1000.0
	if power_kw <= 0.05:
		return 0.0
	return sim.fuel_flow * 3600.0 / power_kw


static func brake_thermal_efficiency(sim: EngineSim) -> float:
	return EngineMetrics._thermal_efficiency(sim, EngineMetrics.brake_power_w(sim))


static func indicated_thermal_efficiency(sim: EngineSim) -> float:
	return EngineMetrics._thermal_efficiency(sim, EngineMetrics.indicated_power_w(sim))


static func _thermal_efficiency(sim: EngineSim, power_w: float) -> float:
	var fuel_w := sim.fuel_flow * 0.001 * sim.fuel.lhv
	if power_w <= 0.0 or fuel_w <= 0.0:
		return 0.0
	return power_w / fuel_w


# Trapped fresh air at intake closing divided by the swept volume filled at ambient density.
static func volumetric_efficiency(sim: EngineSim) -> float:
	var rho := Cylinder.P0 / (Cylinder.R * Cylinder.T0)
	var sum := 0.0
	var n := 0
	for c in sim.cylinders:
		if c.swept <= 0.0 or c.last_fresh_kg <= 0.0:
			continue
		sum += c.last_fresh_kg / (c.swept * rho)
		n += 1
	return sum / n if n > 0 else 0.0


static func mechanical_efficiency(sim: EngineSim) -> float:
	var indicated := EngineMetrics.imep_pa(sim)
	if indicated <= 0.0:
		return 0.0
	return EngineMetrics.bmep_pa(sim) / indicated


static func peak_pressure_pa(sim: EngineSim) -> float:
	var peak := 0.0
	for c in sim.cylinders:
		peak = maxf(peak, c.last_peak_pressure)
	return peak


# Steepest pressure rise of the last cycle, Pa per crank degree.
static func peak_dp_dtheta(sim: EngineSim) -> float:
	var peak := 0.0
	for c in sim.cylinders:
		peak = maxf(peak, c.last_dp_dtheta)
	return peak


static func ca50_deg(sim: EngineSim) -> float:
	return EngineMetrics._mean_angle(sim, func(c) -> float: return c.last_ca50) # both cylinder types have last_ca50


static func burn_10_90_deg(sim: EngineSim) -> float:
	var sum := 0.0
	var n := 0
	for c in sim.cylinders:
		if c.last_burn_10_90 > 0.0:
			sum += c.last_burn_10_90
			n += 1
	return sum / n if n > 0 else 0.0


static func ivc_temp_c(sim: EngineSim) -> float:
	if sim.cylinders.is_empty():
		return 0.0
	var sum := 0.0
	for c in sim.cylinders:
		sum += c.last_ivc_temp
	return sum / sim.cylinders.size() - 273.15


static func residual_fraction(sim: EngineSim) -> float:
	if sim.cylinders.is_empty():
		return 0.0
	var sum := 0.0
	for c in sim.cylinders:
		sum += c.last_residual_fraction
	return sum / sim.cylinders.size()


static func _mean_angle(sim: EngineSim, pick: Callable) -> float:
	var sum := 0.0
	var n := 0
	for c in sim.cylinders:
		var angle: float = pick.call(c)
		if angle >= 0.0:
			sum += angle
			n += 1
	return sum / n if n > 0 else -1.0
