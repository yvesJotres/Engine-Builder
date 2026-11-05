extends SceneTree

# Warm idle with the ECU, for the engines that matter: prints the idle, the spark trim and the idle-air factor.
func _init() -> void:
	await process_frame
	for name in ["Kawasaki ZX-25R (2020)", "Yamaha YZF-R1M (2015)", "Honda CBR150R (K45N)"]:
		var p: Dictionary = Presets.PRESETS[name]
		var spec := EngineSpec.new()
		for key in p.keys():
			spec.set(key, p[key])
		var sim := EngineSim.new()
		for i in 600:
			sim.step(1.0 / 60.0, spec, 0.0, true, true, false, false, 1.0)
		for i in 600:
			sim.step(1.0 / 60.0, spec, 0.0, true, false, false, false, 1.0)
		print("%-24s idle %5.0f rpm, running %s, spark trim %.1f deg, air factor %.3f" % [name, sim.rpm, sim.running, sim.ecu.trim, sim.ecu.air_factor()])
	quit()
