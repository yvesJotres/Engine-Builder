extends SceneTree

func _init() -> void:
	var data: Dictionary = Presets.PRESETS["bugatti_centodieci"]
	var spec := EngineSpec.new()
	for key in data:
		spec.set(key, data[key])
	for rpm in [2250.0, 7050.0]:
		var result := _measure(spec, rpm)
		print("steady %.0f rpm: %.1f N-m, %.1f hp, %.2f bar absolute" % [rpm, result.torque, result.hp, result.pressure / 100000.0])
		if not is_finite(result.torque) or not is_finite(result.pressure):
			print("RESULT: FAIL")
			quit(1)
			return
	print("RESULT: PASS (numerical stability only; not calibrated to factory output)")
	quit()

func _measure(spec: EngineSpec, target_rpm: float) -> Dictionary:
	var sim := EngineSim.new()
	sim.fuel.set_kind(spec.fuel)
	sim.running = true
	var torque_sum := 0.0
	var samples := 0
	var step := 1.0 / 3600.0
	for index in 10800:
		sim.rpm = target_rpm
		sim.omega = target_rpm * TAU / 60.0
		sim.step(step, spec, 1.0, true, false, true, false, 1.0)
		if index >= 7200:
			torque_sum += sim.torque
			samples += 1
	var torque := torque_sum / samples
	return {"torque": torque, "hp": Units.w_to_hp(Units.power_w(torque, target_rpm)), "pressure": sim.intake.pressure}