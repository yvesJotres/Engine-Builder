extends SceneTree

# Measures the Panigale V4 idle against a fixed idle air factor (the ECU's air valve held by hand), with the spark trim left
# to the ECU. Shows whether any air setting can hold 1,200 rpm: if none can, friction is the cause, not the valve.
# Run: godot --headless -s tools/diagnostics/panigale_air_sweep.gd
func _init() -> void:
	await process_frame
	var p: Dictionary = Presets.PRESETS["Ducati Panigale V4 (1,103 cc)"]
	for factor in [0.01, 0.03, 0.1, 0.2, 0.4, 0.7, 1.0]:
		var spec := EngineSpec.new()
		for key in p.keys():
			spec.set(key, p[key])
		var sim := EngineSim.new()
		sim.ecu.manual_air = factor
		var frames := 0
		while sim.rpm < 1000.0 and frames < 3600:
			sim.step(1.0 / 60.0, spec, 0.0, true, true, false, false, 1.0)
			frames += 1
		for i in 60 * 6 + 60: # settle for about 6 seconds after the start
			sim.step(1.0 / 60.0, spec, 0.0, true, false, false, false, 1.0)
		var rpm_sum := 0.0
		var torque_sum := 0.0
		for i in 120:
			sim.step(1.0 / 60.0, spec, 0.0, true, false, false, false, 1.0)
			rpm_sum += sim.rpm
			torque_sum += sim._gas_torque
		print("air x%.2f: idle %6.0f rpm, mean gas torque %6.2f N.m, spark trim %5.1f" % [factor, rpm_sum / 120.0, torque_sum / 120.0, sim.ecu.trim])
	quit()
