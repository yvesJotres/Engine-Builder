extends SceneTree

var _hz := 7200

# Measurements from the current source simulation; factory targets never enter the solver.
func _init() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/performance_references.json"))
	var results := {}
	var only := ""
	var rated_only := false
	var output_name := "current"
	var runner_override := 0.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--preset="):
			only = arg.substr(9)
		elif arg.begins_with("--hz="):
			_hz = maxi(int(arg.substr(5)), 1200)
		elif arg == "--rated-only":
			rated_only = true
		elif arg.begins_with("--output="):
			output_name = arg.substr(9).validate_filename()
		elif arg.begins_with("--runner-length="):
			runner_override = float(arg.substr(16))
		elif arg == "--gd-only":
			Cylinder.use_native = false
	for id in fixture.references:
		if only != "" and only != id:
			continue
		var reference: Dictionary = fixture.references[id]
		var spec := EngineSpec.new()
		for key in Presets.PRESETS[id]:
			spec.set(key, Presets.PRESETS[id][key])
		if runner_override > 0.0:
			spec.runner_length_m = runner_override
		var samples := []
		var targets := [float(reference.torque_rpm), float(reference.power_rpm)]
		for rpm in range(3000, int(spec.redline_rpm), 500):
			if not rated_only and not targets.has(float(rpm)):
				targets.append(float(rpm))
		targets.sort()
		for rpm in targets:
			var sample := _hold(spec, rpm)
			samples.append(sample)
			print("%s %.0f RPM: %.3f Nm %.3f kW" % [id, rpm, sample.torque_nm, sample.power_kw])
		var at_power := {}
		var at_torque := {}
		var peak_power := {"power_kw": -INF}
		var peak_torque := {"torque_nm": -INF}
		for sample in samples:
			if is_equal_approx(sample.target_rpm, float(reference.power_rpm)):
				at_power = sample
			if is_equal_approx(sample.target_rpm, float(reference.torque_rpm)):
				at_torque = sample
			if sample.power_kw > peak_power.power_kw:
				peak_power = sample
			if sample.torque_nm > peak_torque.torque_nm:
				peak_torque = sample
		var power_error: float = at_power.power_kw / float(reference.power_kw) - 1.0
		var torque_error: float = at_torque.torque_nm / float(reference.torque_nm) - 1.0
		results[id] = {"reference": reference, "curve": samples, "power_error": power_error, "torque_error": torque_error,
			"power_pass": absf(power_error) <= 0.03 and absf(peak_power.power_kw / float(reference.power_kw) - 1.0) <= 0.03,
			"torque_pass": absf(torque_error) <= 0.05 and absf(peak_torque.torque_nm / float(reference.torque_nm) - 1.0) <= 0.05,
			"peak_power": peak_power, "peak_torque": peak_torque, "road_status": "unverified", "transient_status": "unverified"}
		results[id]["power_peak_rpm_pass"] = null if rated_only else absf(float(peak_power.target_rpm) - float(reference.power_rpm)) <= 600.0
		results[id]["curve_scope"] = "rated points only" if rated_only else "500 RPM grid plus rated points"
		print("%s power error %+.1f%% torque error %+.1f%%" % [id, power_error * 100, torque_error * 100])
	if only == "":
		for id in Presets.PRESETS:
			if not results.has(id):
				results[id] = {"status": "deferred" if fixture.deferred.has(id) else "unverified", "reason": "No matching manufacturer performance reference registered yet"}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/accuracy"))
	var file := FileAccess.open("res://build/accuracy/%s.json" % output_name, FileAccess.WRITE)
	file.store_string(JSON.stringify({"utc": Time.get_datetime_string_from_system(true), "physics_hz": _hz, "native_requested": Cylinder.use_native, "runner_length_override_m": runner_override, "scope": "steady-speed source simulation; crank torque; open clutch; warm default fluids; 32 complete cycles; no road validation", "results": results}, "  "))
	print("Saved build/accuracy/%s.json" % output_name)
	print("Measurements complete. Road and transient accuracy remain UNVERIFIED; inspect individual output failures.")
	quit()


func _hold(spec: EngineSpec, target: float) -> Dictionary:
	var sim := EngineSim.new()
	sim.audio_enabled = false
	sim.fuel.set_capacity(spec.fuel_capacity_l)
	sim.fuel.set_kind(spec.fuel)
	sim.physics_dt = 1.0 / _hz
	var dt := sim.physics_dt
	var sum := 0.0
	var sum_rpm := 0.0
	var angle := 0.0
	# Independent state at each speed. Warm for one second, then integrate exactly
	# 32 complete 720-degree engine cycles to avoid partial-cycle torque bias.
	for i in _hz:
		sim.rpm = target
		sim.omega = target * TAU / 60.0
		sim.step(dt, spec, 1.0, true, false, true, false, 1.0)
	while angle < 720.0 * 32.0:
		var before: float = sim.cylinders[0].phi
		sim.rpm = target
		sim.omega = target * TAU / 60.0
		sim.step(dt, spec, 1.0, true, false, true, false, 1.0)
		var step_angle: float = minf(sim.cylinders[0].phi - before, 720.0 * 32.0 - angle)
		assert(step_angle > 0.0, "fixed-speed dyno stopped advancing")
		sum += sim.torque * step_angle
		sum_rpm += sim.rpm * step_angle
		angle += step_angle
	var torque := sum / angle
	return {"target_rpm": target, "rpm": sum_rpm / angle, "torque_nm": torque, "power_kw": Units.power_kw(torque, sum_rpm / angle), "imep_bar": sim.imep_pa() / 1e5, "bmep_bar": sim.bmep_pa() / 1e5, "ve": sim.volumetric_efficiency(), "lambda": sim.o2_lambda(), "manifold_pa": sim.intake.pressure}
