extends SceneTree

# Warm idle with the ECU, for the engines that matter: prints the idle, the spark trim and the idle-air factor.
func _init() -> void:
	await process_frame
	for name in ["honda_cbr150r", "honda_cbr250rr", "kawasaki_zx25r", "yamaha_yzf_r1m", "ducati_panigale_v4"]:
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
