extends SceneTree

# A wheel's grip is a function of slip: it peaks at TYRE_SLIP_PEAK and falls away when the wheel is locked. Everything
# ABS does is an attempt to sit on that peak, so the curve is tested first and on its own.
# Run: godot --headless --path . -s tests/unit/sim/wheel_test.gd

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func _init() -> void:
	await process_frame
	var radius := 0.3
	# free rolling: the wheel turns exactly fast enough for the road speed, so there is no slip
	check(absf(Wheel.slip_ratio(20.0, 6.0, radius)) < 1e-6, "a free-rolling wheel slips 0%%")
	# locked: the wheel has stopped, the bike has not
	check(absf(Wheel.slip_ratio(0.0, 20.0, radius) + 1.0) < 1e-6, "a locked wheel slips -100%%")
	# standing still: no divide by zero, and no slip
	check(absf(Wheel.slip_ratio(0.0, 0.0, radius)) < 1e-6, "a bike at rest does not slip")
	# the curve peaks where it says it does
	var peak := Wheel.mu(Wheel.TYRE_SLIP_PEAK)
	check(absf(peak - Wheel.TYRE_MU_PEAK) < 1e-6, "peak grip is %.2f at %.0f%% slip" % [peak, Wheel.TYRE_SLIP_PEAK * 100.0])
	check(Wheel.mu(0.05) < peak and Wheel.mu(0.30) < peak, "grip falls off either side of the peak")
	check(Wheel.mu(1.0) < 0.9 and Wheel.mu(1.0) > 0.6, "a locked wheel keeps %.2f of grip, about 70%% of peak" % Wheel.mu(1.0))
	check(absf(Wheel.mu(-0.12) - peak) < 1e-6, "the curve is symmetric (engine braking has grip too)")
	print("grip: %.2f at 12%% slip, %.2f at 30%%, %.2f locked" % [peak, Wheel.mu(0.3), Wheel.mu(1.0)])

	# ---- integration: braking the wheel slows it, and the ground pushes back ----
	var w := Wheel.new()
	w.radius_m = 0.3
	w.resync(20.0) # 72 km/h
	check(absf(w.omega - 20.0 / 0.3) < 1e-6, "resync puts the wheel in step with the road")
	w.load_n = 1000.0
	# 400 N·m into a wheel carrying 1000 N: far more than the tyre can hold, so it locks quickly
	for i in 60:
		w.advance(1.0 / 60.0, 20.0, 400.0)
	check(w.slip() < -0.5, "400 N·m through a 1000 N wheel locks it (slip %.2f)" % w.slip())
	check(w.locked_time > 0.2, "the wheel records how long it spent locked (%.2f s)" % w.locked_time)
	var peak_grip := Wheel.TYRE_MU_PEAK * 1000.0
	check(w.grip_force() < peak_grip * 0.85 and w.grip_force() > peak_grip * 0.6,
		"a locked wheel makes %.0f N against %.0f N at the peak" % [w.grip_force(), peak_grip])
	# free rolling with no brake it stays in step
	var free := Wheel.new()
	free.resync(15.0)
	free.load_n = 800.0
	free.advance(1.0 / 60.0, 15.0, 0.0)
	check(absf(free.slip()) < 0.02, "no brake, negligible slip (%.4f)" % free.slip())

	# ---- the spec carries the numbers, so a preset can have bigger brakes or a calmer ABS ----
	var spec := EngineSpec.new()
	check(spec.brake_torque_nm > 300.0, "the default caliper can lock the default bike (%.0f N·m)" % spec.brake_torque_nm)
	check(spec.abs_slip_target > 0.05 and spec.abs_slip_target < 0.3, "the ABS target is a real slip value")
	check(spec.abs_cycle_hz > 2.0 and spec.abs_cycle_hz < 20.0, "the ABS cycle rate is a real one (%.0f Hz)" % spec.abs_cycle_hz)
	check(spec.abs_min_speed_kmh > 0.0 and spec.abs_min_speed_kmh < 20.0, "the ABS cuts out at a walking pace (%.0f km/h)" % spec.abs_min_speed_kmh)
	check(spec.wheelbase_m() > 1.0, "the wheelbase is available to the load transfer (%.2f m)" % spec.wheelbase_m())

	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
