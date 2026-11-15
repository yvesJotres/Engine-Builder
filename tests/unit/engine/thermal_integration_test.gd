extends SceneTree


func check_path(native: bool) -> bool:
	Cylinder.use_native = native
	var spec := EngineSpec.new()
	spec.wall_heat_capacity_j_k = 1000.0
	spec.coolant_heat_capacity_j_k = 2000.0
	spec.wall_coolant_conductance_w_k = 100.0
	spec.radiator_conductance_w_k = 0.0
	spec.coolant_temp_c = 20.0
	spec.ambient_temp_k = 293.15
	var sim := EngineSim.new()
	sim.audio_enabled = false
	for i in 120:
		sim.step(1.0 / 60.0, spec, 0.2, true, i < 60, false, false, 1.0)
	var heat := 0.0
	for cylinder in sim.cylinders:
		heat += cylinder.wall_loss_j
	assert(absf(heat) > 0.001)
	var thermal_energy: float = (sim._thermal.wall_k - 293.15) * 1000.0 + (sim._thermal.coolant_k - 293.15) * 2000.0
	assert(absf(thermal_energy - heat) < maxf(1.0e-5, absf(heat) * 1.0e-8))
	assert(absf(sim.coolant_c - (sim._thermal.coolant_k - 273.15)) < 1.0e-9)
	assert(absf(sim.cylinders[0].wall_temp_k - 293.15) > 0.000001)
	spec.wall_coolant_conductance_w_k = 0.0
	sim.step(1.0 / 60.0, spec, 0.0, false, false, false, false, 1.0)
	assert(sim._thermal == null and sim.cylinders[0].wall_temp_k == Cylinder.WALL_TEMP)
	return true


func check_shutdown_cooling() -> bool:
	var spec := EngineSpec.new()
	spec.wall_heat_capacity_j_k = 1000.0
	spec.coolant_heat_capacity_j_k = 2000.0
	spec.wall_coolant_conductance_w_k = 100.0
	spec.radiator_conductance_w_k = 30.0
	spec.coolant_temp_c = 100.0
	spec.ambient_temp_k = 293.15
	var sim := EngineSim.new()
	sim.audio_enabled = false
	for i in 600:
		sim.step(1.0 / 60.0, spec, 0.0, false, false, false, false, 1.0)
	assert(sim.coolant_c < 100.0 and sim.coolant_c > 20.0)
	assert(sim._thermal.wall_k < 373.15 and sim._thermal.wall_k > sim._thermal.coolant_k)
	var remaining: float = (sim._thermal.wall_k - spec.ambient_temp_k) * 1000.0 + (sim._thermal.coolant_k - spec.ambient_temp_k) * 2000.0
	assert(absf(remaining + sim._thermal.rejected_j - 80.0 * 3000.0) < 0.001)
	return true


func check_two_stroke() -> bool:
	var spec := EngineSpec.new()
	for key in Presets.PRESETS["yamaha_rd350"]:
		spec.set(key, Presets.PRESETS["yamaha_rd350"][key])
	spec.wall_heat_capacity_j_k = 1000.0
	spec.coolant_heat_capacity_j_k = 2000.0
	spec.wall_coolant_conductance_w_k = 100.0
	spec.radiator_conductance_w_k = 0.0
	spec.coolant_temp_c = 20.0
	spec.ambient_temp_k = 293.15
	var sim := EngineSim.new()
	sim.audio_enabled = false
	for i in 120:
		sim.step(1.0 / 60.0, spec, 0.2, true, i < 60, false, false, 1.0)
	var heat := 0.0
	for cylinder in sim.cylinders:
		heat += cylinder.wall_loss_j
	var thermal_energy: float = (sim._thermal.wall_k - 293.15) * 1000.0 + (sim._thermal.coolant_k - 293.15) * 2000.0
	assert(absf(heat) > 0.001 and absf(thermal_energy - heat) < maxf(1.0e-5, absf(heat) * 1.0e-8))
	assert(absf(sim.coolant_c - (sim._thermal.coolant_k - 273.15)) < 1.0e-9)
	spec.wall_coolant_conductance_w_k = 0.0
	sim.step(1.0 / 60.0, spec, 0.0, false, false, false, false, 1.0)
	assert(sim._thermal == null and sim.cylinders[0].wall_temp_k == TwoStrokeCylinder.WALL_TEMP)
	return true


func _init() -> void:
	var invalid := EngineSpec.new()
	assert(not invalid.thermal_balance_enabled())
	invalid.wall_heat_capacity_j_k = 1000.0
	assert(invalid.validation_warning().begins_with("Thermal balance needs"))
	invalid.coolant_heat_capacity_j_k = 2000.0
	invalid.wall_coolant_conductance_w_k = 100.0
	assert(invalid.thermal_balance_enabled())
	invalid.radiator_conductance_w_k = -1.0
	assert(not invalid.thermal_balance_enabled() and invalid.validation_warning().begins_with("Thermal balance needs"))
	invalid.radiator_conductance_w_k = 0.0
	invalid.stroke_type = "two_stroke"
	assert(invalid.thermal_balance_enabled())
	if not check_path(false) or not check_path(true) or not check_shutdown_cooling() or not check_two_stroke():
		printerr("thermal_integration_test: FAIL")
		quit(1)
		return
	Cylinder.use_native = true
	print("thermal_integration_test: PASS")
	quit()
