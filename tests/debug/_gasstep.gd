extends SceneTree
func _mass(gas) -> float:
	var m := 0.0
	for i in gas._n:
		m += gas._rho[i] * gas._area[i] * gas._dx[i]
	return m
func _init() -> void:
	var spec := EngineSpec.new()
	var p: Dictionary = Presets.PRESETS["yamaha_rd350"]
	for key in p.keys():
		spec.set(key, p[key])
	var ports: Array[Vector3] = [Vector3(-0.4, 1.2, 0.4), Vector3(0.4, 1.2, 0.4)]
	var gas := ExhaustGas.new()
	gas.build(ExhaustLayout.build(spec, ports))
	gas.record_audio = false
	var h := gas._cfl_dt
	print("STEP cfl_us %.3f cell_of_port %d" % [h * 1.0e6, gas._port_cell(0)])
	for k in 5:
		var m0 := _mass(gas)
		gas.apply_valve(0, 0.01, 0.0)
		gas._step(h)
		var dm := _mass(gas) - m0
		print("STEP k%d dm_ug %.4f expected_ug %.4f port_rho %.4f" % [k, dm * 1.0e9, 0.01 * h * 1.0e9, gas._rho[gas._port_cell(0)]])
	for k in 3:
		var m1 := _mass(gas)
		gas.apply_valve(0, 0.0, 0.0)
		gas._step(h)
		print("STEP off k%d dm_ug %.4f" % [k, (_mass(gas) - m1) * 1.0e9])
	quit()
