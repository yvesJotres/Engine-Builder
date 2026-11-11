extends SceneTree

# Probe: where the full-throttle energy goes. Runs the same warm-up and throttle as sensors_test, then over the last
# second reports the heat lost to the walls as a share of the fuel energy burnt, and the exhaust temperature.
# Usage: godot --headless --path . -s res://tools/diagnostics/wall_energy_probe.gd

const LHV := 44.0e6 # J/kg, petrol
const STOICH := 14.7

func _init() -> void:
	var spec := EngineSpec.new()
	var sim := EngineSim.new()
	for i in 720:
		sim.step(1.0 / 60.0, spec, 0.0, true, true, false, false, 1.0)
	for i in 600:
		sim.step(1.0 / 60.0, spec, 1.0, true, false, false, false, 1.0)
	var start_loss := 0.0
	for c in sim.cylinders:
		start_loss += c.wall_loss_j
	for i in 60:
		sim.step(1.0 / 60.0, spec, 1.0, true, false, false, false, 1.0)
	var end_loss := 0.0
	var fuel_power := 0.0
	var peak := 0.0
	for c in sim.cylinders:
		end_loss += c.wall_loss_j
		var cycles_per_s: float = sim.rpm / 60.0 / 2.0
		fuel_power += c.last_fresh_kg / STOICH * LHV * cycles_per_s
		peak = maxf(peak, c.last_peak_temp)
	var wall_power := (end_loss - start_loss) / 1.0
	print("rpm %.0f, cylinders %d" % [sim.rpm, sim.cylinders.size()])
	print("fuel power %.0f W, wall heat %.0f W, wall share %.1f %%" % [fuel_power, wall_power, 100.0 * wall_power / maxf(fuel_power, 1.0)])
	print("exhaust temperature %.0f C, last peak gas temperature %.0f K" % [sim.exhaust_temp_c(), peak])
	quit(0)
