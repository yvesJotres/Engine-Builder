extends SceneTree

# Diagnostic: fuel energy balance averaged over one second at a time: brake power (mean torque x mean crank speed) against
# fuel power (mean flow x heating value), for petrol and E85, full throttle in neutral. Print only.
func _init() -> void:
	await process_frame
	for kind in ["ron95", "e85"]:
		var spec := EngineSpec.new()
		var sim := EngineSim.new()
		sim.fuel.set_kind(kind)
		for i in 720:
			sim.step(1.0 / 60.0, spec, 0.0, true, true, false, false, 1.0)
		print("%s  (afr %.1f, lhv %.1f MJ/kg, latent %.0f kJ/kg, octane %.0f)" % [kind, sim.fuel.afr, sim.fuel.lhv / 1.0e6, sim.fuel.latent / 1.0e3, sim.fuel.octane])
		for sec in 4:
			var tq := 0.0
			var om := 0.0
			var fl := 0.0
			for i in 60:
				sim.step(1.0 / 60.0, spec, 1.0, true, false, false, false, 1.0)
				tq += sim.torque
				om += sim.rpm * TAU / 60.0
				fl += sim.fuel_flow
			tq /= 60.0
			om /= 60.0
			fl /= 60.0
			var brake := tq * om
			var fuel_w := fl / 1000.0 * sim.fuel.lhv
			print("  second %d: %5.0f rpm  mean torque %5.1f N·m  mean flow %5.2f g/s  brake %5.1f kW  fuel %5.1f kW  efficiency %4.1f %%" % [sec + 1, sim.rpm, tq, fl, brake / 1000.0, fuel_w / 1000.0, 100.0 * brake / maxf(fuel_w, 1.0)])
	quit(0)
