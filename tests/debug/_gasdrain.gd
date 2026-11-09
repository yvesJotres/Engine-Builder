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
	for k in 14:
		var drain := k < 3
		gas.apply_valve(0, -0.01 if drain else 0.0, 0.0)
		gas.advance(0.02)
		var mass := 0.0
		for i in gas._n:
			mass += gas._rho[i] * gas._area[i] * gas._dx[i]
		print("DRAIN t%02d drain %s port0 %.1f kPa mass_ug %.1f tail %.5f" % [k, str(drain), gas.port_pressure(0) / 1000.0, mass * 1.0e9, gas.tail_volume_flow()])
	quit()
