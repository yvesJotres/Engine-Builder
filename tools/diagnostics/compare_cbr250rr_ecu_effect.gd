extends SceneTree

# Diagnostic only: compares the physical CBR250RR model with and without the
# decoded N04 table layer.  Raw fuel/torque/TBW schema meanings are not proven,
# so this prevents an ECU interpretation from being mistaken for a gas-model
# defect.  Run: godot --headless --path . -s tools/diagnostics/compare_cbr250rr_ecu_effect.gd

const SAMPLE_RPMS := [11000.0, 12500.0]


func _init() -> void:
	for native_enabled in [true, false]:
		Cylinder.use_native = native_enabled
		for enabled in [false, true]:
			var spec := EngineSpec.new()
			var preset: Dictionary = Presets.PRESETS["honda_cbr250rr"]
			for key in preset:
				spec.set(key, preset[key])
			if not enabled:
				spec.ecu_binary = ""
			print("native " + ("enabled" if native_enabled else "disabled") + ", ECU tables " + ("enabled" if enabled else "disabled"))
			for target_rpm in SAMPLE_RPMS:
				var sample := _hold(spec, target_rpm)
				print("  %.0f rpm: %.2f N.m, %.2f kW, BMEP %.1f bar, VE %.0f%%, MAP %.1f kPa, lambda %.3f, BTE %.0f%%" % [sample.rpm, sample.torque, Units.power_kw(sample.torque, sample.rpm), sample.bmep_bar, sample.ve * 100.0, sample.map_kpa, sample.lambda, sample.bte * 100.0])
	Cylinder.use_native = true
	quit()


func _hold(spec: EngineSpec, target_rpm: float) -> Dictionary:
	var sim := EngineSim.new()
	sim.audio_enabled = false
	sim.physics_dt = 1.0 / 2400.0
	sim.running = true
	var torque_sum := 0.0
	var rpm_sum := 0.0
	var ve_sum := 0.0
	var map_sum := 0.0
	var lambda_sum := 0.0
	var bmep_sum := 0.0
	var bte_sum := 0.0
	var count := 0
	for step in 2400:
		sim.omega = target_rpm * TAU / 60.0
		sim.rpm = target_rpm
		sim.step(sim.physics_dt, spec, 1.0, true, false, true, false, 1.0)
		if step >= 1200:
			torque_sum += sim.torque
			rpm_sum += sim.rpm
			ve_sum += sim.volumetric_efficiency()
			map_sum += sim.intake.pressure / 1000.0
			lambda_sum += sim.o2_lambda()
			bmep_sum += sim.bmep_pa() / 1.0e5
			bte_sum += sim.brake_thermal_efficiency()
			count += 1
	return {"torque": torque_sum / count, "rpm": rpm_sum / count, "ve": ve_sum / count, "map_kpa": map_sum / count, "lambda": lambda_sum / count, "bmep_bar": bmep_sum / count, "bte": bte_sum / count}
