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
	print("TIME cfl_us %.2f n %d" % [gas._cfl_dt * 1.0e6, gas._n])
	var m0 := 0.0
	for i in gas._n:
		m0 += gas._rho[i] * gas._area[i] * gas._dx[i]
	gas.apply_valve(0, -0.01, 0.0)
	var t0 := Time.get_ticks_usec()
	gas.advance(0.02)
	var m1 := 0.0
	for i in gas._n:
		m1 += gas._rho[i] * gas._area[i] * gas._dx[i]
	print("TIME advance(0.02) removed_ug %.1f expected_ug %.1f us %d" % [(m0 - m1) * 1.0e9, 0.01 * 0.02 * 1.0e9, Time.get_ticks_usec() - t0])
	quit()
