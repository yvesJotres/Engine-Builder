extends SceneTree

# A prescribed crank trajectory isolates the new runner/configuration from
# feedback through the starter, idle controller and changing physics steps.
func _init() -> void:
	if not Cylinder.native_available or int(ClassDB.class_call_static("CylinderKernel", "config_size")) < 27:
		push_error("R1 runner test requires the rebuilt native kernel")
		quit(2)
		return
	var spec := EngineSpec.new()
	for key in Presets.PRESETS.yamaha_yzf_r1m:
		spec.set(key, Presets.PRESETS.yamaha_yzf_r1m[key])
	var legacy := Cylinder.new()
	legacy.set_cams(EngineSpec.new())
	assert(legacy.runner_area == Cylinder.RUNNER_AREA)
	var old_config := Cylinder.new()
	for c in [legacy, old_config]:
		c.setup(57.3, 57.8, 11.3)
		c.set_cams(EngineSpec.new())
		c.start_at(180.0)
	old_config._build_native_config()
	old_config._cfg.resize(26) # old source packs no runner-area value
	var legacy_tank := FuelTank.new()
	var old_tank := FuelTank.new()
	for i in 720:
		Cylinder.use_native = false
		var a := legacy.advance(1.0, 1.0 / 36000.0, Cylinder.P0, Cylinder.T0, 700.0, false, legacy_tank, 1.0)
		Cylinder.use_native = true
		var b := old_config.advance(1.0, 1.0 / 36000.0, Cylinder.P0, Cylinder.T0, 700.0, false, old_tank, 1.0)
		assert(absf(a.x - b.x) < 1e-6 * maxf(1.0, absf(a.x)), "old native configuration changed legacy runner physics")
	for rpm in [11500.0, 13500.0]:
		var gd := Cylinder.new()
		var native := Cylinder.new()
		for c in [gd, native]:
			c.setup(spec.bore_mm, spec.stroke_mm, spec.compression_ratio, spec.reciprocating_kg(), spec.rod_over_crank_radius())
			c.set_cams(spec)
			c.start_at(0.0)
		assert(is_equal_approx(gd.runner_area, PI * 0.045 * 0.045 / 4.0))
		var tank_gd := FuelTank.new()
		var tank_native := FuelTank.new()
		var dt: float = 1.0 / (rpm * 6.0)
		var max_error := 0.0
		var work_gd := 0.0
		var work_native := 0.0
		for i in 720 * 20:
			Cylinder.use_native = false
			var a := gd.advance(1.0, dt, Cylinder.P0, 280.0, 720.0 - EngineAir.spark_advance_deg(rpm), true, tank_gd, 0.85)
			Cylinder.use_native = true
			var b := native.advance(1.0, dt, Cylinder.P0, 280.0, 720.0 - EngineAir.spark_advance_deg(rpm), true, tank_native, 0.85)
			max_error = maxf(max_error, absf(a.x - b.x) / maxf(1.0, absf(a.x)))
			if i >= 720 * 10:
				work_gd += a.x
				work_native += b.x
		assert(max_error < 1e-6, "native/script R1 cylinder torque mismatch")
		assert(absf(work_gd - work_native) / maxf(absf(work_gd), 1.0) < 1e-6)
		for field in ["mass", "temp", "pressure", "runner_q", "port_p", "last_fresh_kg", "wall_loss_j"]:
			assert(absf(gd.get(field) - native.get(field)) <= 1e-6 * maxf(1.0, absf(gd.get(field))), "native/script R1 state mismatch: " + field)
		print("R1 %.0f RPM: 20 cycles native/script agree, max torque relative error %.9f" % [rpm, max_error])
	# Changing the runner must invalidate the cached cylinder configuration.
	var sim := EngineSim.new()
	sim._build_cylinders(spec)
	var old_cylinder: Cylinder = sim.cylinders[0]
	spec.runner_bore_mm = 38.0
	sim._build_cylinders(spec)
	assert(sim.cylinders[0] != old_cylinder)
	assert(is_equal_approx(sim.cylinders[0].runner_area, PI * 0.038 * 0.038 / 4.0))
	# The stock clutch must transmit the published engine torque at the crank.
	# A high-inertia roller isolates clutch holding from tyre grip/road drag.
	var loaded := EngineSim.new()
	loaded.cell_mass_kg = 1e6
	loaded.clutch_engage = 1.0
	var ratio: float = spec.primary_ratio * spec.final_drive * spec.gear_ratios[5]
	var radius := EngineSim.tire_radius_m(spec)
	loaded.omega = 11500.0 * TAU / 60.0
	loaded.speed = loaded.omega * radius / ratio
	for i in 2400:
		loaded._advance_driveline(1.0 / 2400.0, spec, 112.4, spec.rotating_inertia(), ratio, radius)
	var slip_rpm: float = (loaded.omega - loaded.speed * ratio / radius) * 60.0 / TAU
	assert(absf(slip_rpm) < 20.0, "stock R1 clutch slips continuously below rated torque")
	print("R1 runner geometry/configuration: PASS")
	quit()
