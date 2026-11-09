extends SceneTree
func _init() -> void:
	var spec := EngineSpec.new()
	var p: Dictionary = Presets.PRESETS["yamaha_rd350"]
	for key in p.keys():
		spec.set(key, p[key])
	var ports: Array[Vector3] = [Vector3(-0.4, 1.2, 0.4), Vector3(0.4, 1.2, 0.4)]
	var gas := ExhaustGas.new()
	gas.build(ExhaustLayout.build(spec, ports))
	gas.record_audio = false
	var cp := 1000.0
	for k in 12:
		var on := k < 4
		gas.apply_valve(0, 0.01 if on else 0.0, (0.01 * cp * 900.0) if on else 0.0)
		gas.advance(0.02)
		var mass := 0.0
		var energy := 0.0
		for i in gas._n:
			mass += gas._rho[i] * gas._area[i] * gas._dx[i]
			energy += gas._re[i] * gas._area[i] * gas._dx[i]
		print("INJ t%02d on %s mass %.6f energy %.1f port0 %.1f kPa tail %.5f cells %d" % [k, str(on), mass, energy, gas.port_pressure(0) / 1000.0, gas.tail_volume_flow(), gas._n])
	quit()
