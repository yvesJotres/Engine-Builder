extends SceneTree
func _init() -> void:
	var spec := EngineSpec.new()
	var p: Dictionary = Presets.PRESETS["yamaha_rd350"]
	for key in p.keys():
		spec.set(key, p[key])
	var ports: Array[Vector3] = [Vector3(-0.4, 1.2, 0.4), Vector3(0.4, 1.2, 0.4)]
	var layout := ExhaustLayout.build(spec, ports)
	var gas := ExhaustGas.new()
	gas.build(layout)
	gas.record_audio = false
	print("REST cells %d min_dx %.3f cfl %.2e" % [gas._n, gas._min_dx, gas._cfl_dt])
	for k in 6:
		gas.advance(0.2)
		var mass := 0.0
		for i in gas._n:
			mass += gas._rho[i] * gas._area[i] * gas._dx[i]
		print("REST t%d station0 %.0f kPa tail_flow %.4f  port0 %.0f  mass_total %.6f" % [k, gas.station_pressure(0) / 1000.0, gas.tail_volume_flow(), gas.port_pressure(0) / 1000.0, mass])
	quit()
