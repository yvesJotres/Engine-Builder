extends SceneTree

var _fails := 0

func _init() -> void:
	var spec := EngineSpec.new()
	spec.max_boost_ratio = 2.5
	spec.intake_area_scale = 10.0
	spec.manifold_volume_scale = 20.0
	var intake := EngineAir.new()
	for step in 7200:
		intake.manifold_update(1.0 / 3600.0, 1.0, 0.0, spec, 7000.0)
	check(intake.pressure > EngineAir.P0 * 1.5, "turbo develops positive manifold pressure")
	check(intake.pressure <= EngineAir.P0 * spec.max_boost_ratio, "boost stays within the configured maximum")
	for step in 7200:
		intake.manifold_update(1.0 / 3600.0, 0.0, 0.0, spec, 7000.0)
	check(intake.boost_ratio < 1.1, "boost falls after throttle release")
	var natural := EngineAir.new()
	var stock := EngineSpec.new()
	for step in 3600:
		natural.manifold_update(1.0 / 3600.0, 1.0, 0.0, stock, 7000.0)
	check(natural.pressure <= EngineAir.P0, "naturally aspirated engines remain unboosted")
	var electric_spec := EngineSpec.new()
	electric_spec.max_boost_ratio = 1.25
	electric_spec.electric_compressor = true
	var electric := EngineAir.new()
	for step in 3600:
		electric.manifold_update(1.0 / 3600.0, 1.0, 0.0, electric_spec, 1000.0)
	check(electric.pressure > EngineAir.P0 * 1.1, "electric compressor can boost independently of engine rpm")
	var off := EngineAir.new()
	for step in 1000:
		off.manifold_update(0.001, 1.0, 0.0, electric_spec, 0.0, false)
	check(is_equal_approx(off.boost_ratio, 1.0) and off.compressor_load == 0.0, "stopped engine does not run electric compressor")
	electric_spec.compressor_charge_w = 0.0
	electric_spec.compressor_battery_wh = 1.0
	var battery := EngineAir.new()
	for step in 1000:
		battery.manifold_update(0.01, 1.0, 0.0, electric_spec, 1000.0, true)
	check(battery.compressor_charge < 0.1 and battery.compressor_charge >= 0.0, "electric boost respects finite battery energy")
	check(is_finite(battery.pressure) and is_finite(battery.boost_ratio), "depleted compressor state stays finite")
	var fuel := FuelTank.new()
	fuel.mass_kg *= 0.5
	fuel.set_capacity(100.0)
	check(is_equal_approx(fuel.fraction(), 0.5), "changing fuel capacity preserves fill percentage")
	check(absf(fuel.mass_kg - 37.25) < 0.001, "100-litre tank uses the selected fuel density")
	var car := EngineSpec.new()
	car.wheel_radius_m = 0.35545
	check(is_equal_approx(EngineSim.tire_radius_m(car), 0.35545), "vehicle-specific tire radius is used")
	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)

func check(ok: bool, message: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + message)
