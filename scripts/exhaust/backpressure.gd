class_name Backpressure
extends RefCounted

# Mean exhaust backpressure from the geometry of the pipe, not from a number picked to feel right.
#
# A pipe resists flow in three ways, and each has a closed form:
#
#   1. Friction along the wall:  dp = f * (L / D) * (rho * v^2 / 2),  Darcy-Weisbach, f = 0.045 for a rough steel or
#      aluminium exhaust tube at the Reynolds numbers an engine runs at (10^4..10^5, rough-wall regime).
#   2. Sudden area changes:      dp = K * (rho * v^2 / 2), with K = (1 - A1/A2)^2 for an expansion into a wider box (the
#      collector, the catalyst shell, the muffler can) and K = 0.5 * (1 - A2/A1) for a contraction back down to tube size.
#      These are the standard Borda-Carnot and entrance-loss coefficients, so the size of the muffler sets its own loss.
#   3. The exit to still air:    dp = 1.0 * (rho * v^2 / 2): the jet has to be accelerated into the atmosphere and the
#      momentum is lost.
#
# Velocity comes from the mass flow and the local area, v = mdot / (rho * A), and the density from the gas temperature,
# rho = p / (R * T), so a hotter pipe passes the same mass with less pressure: a red-hot header hurts backpressure less than
# a cold one. Every pipe in the chain is in series, so the pressure drops add.
#
# This is the MEAN backpressure. The instantaneous pressure at the valve is a wave, and that is what ExhaustGas solves;
# this model is what the engine feels on the path where that solver is off, and it is the number the sound uses.

const FRICTION_F := 0.045 # rough-wall friction factor for exhaust tube at Re 1e4..1e5
const R := 287.0 # J/kg·K
const EXIT_K := 1.0 # jet into still air
const SCENE_TO_M := 0.1 # 1 scene unit = 10 cm
const MIN_AREA_M2 := 1.0e-6


# Mean gauge pressure (Pa above atmosphere) for a mean mass flow through this layout, with the gas at gas_temp_k.
static func mean_gauge_pa(layout: ExhaustLayout, mean_mdot_kg_s: float, gas_temp_k: float) -> float:
	if layout == null or mean_mdot_kg_s <= 0.0 or layout.pipes.is_empty():
		return 0.0
	var temp := maxf(gas_temp_k, 200.0)
	var rho := 101325.0 / (R * temp) # ideal gas at the pipe's own temperature
	var branches := maxi(1, _cylinders_fed(layout))
	var total := 0.0
	var previous_area := 0.0
	for pipe in layout.pipes:
		var radius_scene := _mean_radius(pipe)
		if radius_scene <= 0.0:
			continue
		var radius_m := radius_scene * SCENE_TO_M
		var area := maxf(PI * radius_m * radius_m, MIN_AREA_M2)
		# the primaries each carry one cylinder's share of the flow; everything downstream carries all of it
		var share := 1.0 / float(branches) if pipe.kind == "primary" else 1.0
		var mdot := mean_mdot_kg_s * share
		var velocity := mdot / (rho * area)
		var dynamic := 0.5 * rho * velocity * velocity
		# friction along this pipe's own length
		var friction_k := FRICTION_F * pipe.length_m() / maxf(2.0 * radius_m, 1.0e-4)
		total += friction_k * dynamic
		# the area change where this pipe meets the previous one
		if previous_area > MIN_AREA_M2:
			if area > previous_area:
				var ratio := previous_area / area
				total += (1.0 - ratio) * (1.0 - ratio) * dynamic
			else:
				total += 0.5 * (1.0 - area / previous_area) * dynamic
		previous_area = area
	# the tailpipe empties into still air
	if previous_area > MIN_AREA_M2:
		var tail_mdot := mean_mdot_kg_s
		var tail_velocity := tail_mdot / (rho * previous_area)
		total += EXIT_K * 0.5 * rho * tail_velocity * tail_velocity
	return maxf(total, 0.0)


static func _cylinders_fed(layout: ExhaustLayout) -> int:
	var count := 0
	for pipe in layout.pipes:
		if pipe.kind == "primary":
			count += 1
	return count


static func _mean_radius(pipe: ExhaustLayout.Pipe) -> float:
	if pipe.radii.is_empty():
		return 0.0
	var sum := 0.0
	for r in pipe.radii:
		sum += r
	return sum / float(pipe.radii.size())
