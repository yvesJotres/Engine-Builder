extends SceneTree

# Diagnostic: the CBR150R's gas torque near 7,000 rpm in the whole sim, at full throttle in neutral, with the volumetric-efficiency
# scale at its current value and at 1.0. The clutch stays out, so the engine is free to rev and the torque is the gas torque alone.
# Print only.

func _init() -> void:
	await process_frame
	for scale in [0.72, 1.0]:
		var spec := EngineSpec.new()
		spec.ve_scale = scale
		var sim := EngineSim.new()
		for i in 720:
			sim.step(1.0 / 60.0, spec, 0.0, true, true, false, false, 1.0)
		for i in 600:
			sim.step(1.0 / 60.0, spec, 0.0, true, false, false, false, 1.0)
		var sum := 0.0
		var n := 0
		for i in 1800:
			sim.step(1.0 / 60.0, spec, 1.0, true, false, false, false, 1.0)
			if sim.rpm > 6500.0 and sim.rpm < 7500.0:
				sum += sim._gas_torque
				n += 1
		print("ve_scale %.2f: mean gas torque %5.2f N·m near 7000 rpm (%d steps)" % [scale, sum / maxf(n, 1), n])
	quit(0)
