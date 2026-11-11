extends SceneTree

# The CBR250RR preset must apply only the verified N04 ECU limiter at runtime.
# Run: Godot --headless --path . -s tests/unit/ecu/ecu_runtime_calibration_test.gd

var _failures := 0


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		push_error("ecu_runtime_calibration_test: " + message)


func _init() -> void:
	await process_frame
	var cbr: Dictionary = Presets.PRESETS.get("honda_cbr250rr", {})
	_check(cbr.get("ecu_binary", "") == "res://ecu_bins/CBR250RR-38770-K64-N04_BIN.bin", "CBR250RR preset supplies the N04 binary")
	var sim := EngineSim.new()
	var spec := EngineSpec.new()
	spec.redline_rpm = 15000.0
	spec.ecu_binary = "res://ecu_bins/CBR250RR-38770-K64-N04_BIN.bin"
	sim.step(1.0 / 60.0, spec, 0.0, false, false, false, false, 1.0)
	_check(is_equal_approx(sim.effective_limiter_rpm(spec), 14000.0), "N04 limiter caps the CBR250RR at 14000 RPM")
	_check(sim.ecu_calibration_status().contains(ECUBinaryParser.N04_LAYOUT), "runtime reports verified N04 layout")
	sim.gear.gear = 1
	sim.rpm = 10000.0
	var mapped_throttle := sim.ecu_throttle(0.5)
	_check(mapped_throttle > 0.0 and mapped_throttle <= 1.0, "TBW table produces a bounded throttle command")
	var torque_cap := sim.ecu_torque_throttle_cap()
	_check(torque_cap > 0.0 and torque_cap <= 1.0, "per-gear torque table produces a bounded throttle cap")
	var lambda_mult := sim.ecu_fuel_lambda_multiplier(mapped_throttle)
	_check(lambda_mult >= 0.85 and lambda_mult <= 1.20, "fuel pulse table produces a bounded lambda correction")
	var advance := sim.ecu_ignition_advance_deg(20.0)
	_check(advance >= -10.0 and advance <= 55.0, "ignition tables produce a bounded advance")
	_check(not sim.ecu_speed_limited(), "speed limiter is clear at rest")
	sim.speed = 60.0
	_check(sim.ecu_speed_limited(), "speed limiter cuts above its ECU threshold")
	sim.speed = 0.0

	var safer_spec := EngineSpec.new()
	safer_spec.redline_rpm = 13000.0
	safer_spec.ecu_binary = spec.ecu_binary
	sim.step(1.0 / 60.0, safer_spec, 0.0, false, false, false, false, 1.0)
	_check(is_equal_approx(sim.effective_limiter_rpm(safer_spec), 13000.0), "a lower user redline stays in force")

	if _failures == 0:
		print("ecu_runtime_calibration_test: PASSED")
		quit(0)
		return
	push_error("ecu_runtime_calibration_test: %d failures" % _failures)
	quit(1)
