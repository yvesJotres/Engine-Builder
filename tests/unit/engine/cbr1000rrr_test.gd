extends SceneTree

func _init() -> void:
	var spec := EngineSpec.new()
	for key in Presets.PRESETS.honda_cbr1000rrr_sp:
		spec.set(key, Presets.PRESETS.honda_cbr1000rrr_sp[key])
	assert(spec.validation_warning().is_empty())
	assert(spec.bore_mm == 81.0 and spec.stroke_mm == 48.5 and spec.compression_ratio == 13.0)
	assert(spec.has_abs and spec.has_traction_control and spec.has_quickshifter and spec.has_launch_control)
	assert(spec.road_mass_kg() == 276.0)
	assert(absf(EngineSim.tire_radius_m(spec) - 0.3259) < 0.000001)
	assert(spec.gear_ratios == [2.615, 2.058, 1.700, 1.478, 1.333, 1.214])
	if not Cylinder.native_available:
		push_error("CBR1000RR-R parity requires the native kernel")
		quit(2)
		return
	for rpm in [12500.0, 14500.0]:
		var gd := Cylinder.new()
		var native := Cylinder.new()
		for c in [gd, native]:
			c.setup(spec.bore_mm, spec.stroke_mm, spec.compression_ratio, spec.reciprocating_kg(), spec.rod_over_crank_radius())
			c.set_cams(spec)
			c.start_at(0.0)
		var a_tank := FuelTank.new()
		var b_tank := FuelTank.new()
		for i in 720 * 20:
			Cylinder.use_native = false
			var a := gd.advance(1.0, 1.0 / (rpm * 6.0), Cylinder.P0, 280.0, 720.0 - EngineAir.spark_advance_deg(rpm), true, a_tank, 0.85)
			Cylinder.use_native = true
			var b := native.advance(1.0, 1.0 / (rpm * 6.0), Cylinder.P0, 280.0, 720.0 - EngineAir.spark_advance_deg(rpm), true, b_tank, 0.85)
			assert(absf(a.x - b.x) <= 1e-6 * maxf(1.0, absf(a.x)), "CBR1000RR-R native/script cylinder torque mismatch")
		assert(absf(gd.pressure - native.pressure) < 1e-6 * gd.pressure)
		print("CBR1000RR-R %.0f rpm: 20 prescribed cycles native/script agree" % rpm)
	print("CBR1000RR-R specification and native parity: PASS")
	quit()
