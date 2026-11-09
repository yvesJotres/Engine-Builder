extends SceneTree

# Wide-open CBR250RR against the Honda April 2017 factbook (type 2BK-MC51):
# 28 kW (38 PS) at 12,500 rpm, 23 N·m at 11,000 rpm.
# Sixth gear at 12,500 rpm is 170 km/h with the factbook ratios and a 140/70-17 tyre,
# which is the true speed behind the 179 km/h speedometer figure from the Indonesian road test.
# Run: godot --headless -s tests/integration/dyno/dyno_cbr250rr.gd

const POWER_KW := 28.0
const POWER_RPM := 12500.0
const TORQUE_NM := 23.0
const TORQUE_RPM := 11000.0
const SIXTH_GEAR_KMH_AT_POWER_RPM := 170.0 # kinematic check, not measured achievable top speed

var _fails := 0


func check(ok: bool, msg: String) -> void:
	print(("ok   " if ok else "FAIL ") + msg)
	if not ok:
		_fails += 1


func _init() -> void:
	var spec := EngineSpec.new()
	var preset: Dictionary = Presets.PRESETS["honda_cbr250rr"]
	for key in preset:
		spec.set(key, preset[key])
	var sim := EngineSim.new()
	sim.audio_enabled = false
	sim.physics_dt = 1.0 / 2400.0
	print("Honda CBR250RR MC51  %.0f cc  compression %.1f  redline %.0f" % [spec.displacement_cc, spec.compression_ratio, spec.redline_rpm])
	var best_kw := 0.0
	var best_kw_rpm := 0.0
	var best_nm := 0.0
	var best_nm_rpm := 0.0
	var at_power := {}
	var at_torque := {}
	var hold_rpm := 0.0
	for rpm in [4000, 6000, 8000, 9000, 10000, 11000, 12000, 12500, 13000, 13500]:
		var sample := _hold(sim, spec, float(rpm))
		var kw := Units.power_kw(sample.torque, sample.rpm)
		var ps := kw * 1000.0 / 735.5
		var speed := _kmh(spec, sample.rpm, 6)
		print("%5.0f rpm   %5.2f N·m   %5.2f kW (%4.1f PS)   6th %5.1f km/h" % [sample.rpm, sample.torque, kw, ps, speed])
		if kw > best_kw:
			best_kw = kw
			best_kw_rpm = sample.rpm
		if sample.torque > best_nm:
			best_nm = sample.torque
			best_nm_rpm = sample.rpm
		if absf(sample.rpm - POWER_RPM) < absf(hold_rpm - POWER_RPM):
			at_power = {"rpm": sample.rpm, "torque": sample.torque, "kw": kw, "kmh": speed}
			hold_rpm = sample.rpm
		if absf(float(rpm) - TORQUE_RPM) < 100.0:
			at_torque = {"rpm": sample.rpm, "torque": sample.torque}
	print("peak power %.2f kW (%.1f PS) at %.0f rpm" % [best_kw, best_kw * 1000.0 / 735.5, best_kw_rpm])
	print("peak torque %.2f N·m at %.0f rpm" % [best_nm, best_nm_rpm])
	print("at 11,000 rpm: %.2f N·m (factbook 23 N·m)" % at_torque.torque)
	print("at 12,500 rpm: %.2f kW, %.1f PS, %.1f km/h in 6th" % [at_power.kw, at_power.kw * 1000.0 / 735.5, at_power.kmh])
	for gear in range(1, spec.gear_ratios.size() + 1):
		print("gear %d at 12,500 rpm: %.1f km/h" % [gear, _kmh(spec, POWER_RPM, gear)])
	var v := float(at_power.kmh) / 3.6
	var wheel_kw := float(at_power.torque) * (float(at_power.rpm) * TAU / 60.0) * EngineSim.DRIVE_EFFICIENCY / 1000.0
	var road_kw := sim.road_resistance(v, spec.vehicle_kg, spec.drag_area_m2) * v / 1000.0
	print("at that speed the wheel has %.2f kW and the road takes %.2f kW" % [wheel_kw, road_kw])
	check(absf(at_power.kw / POWER_KW - 1.0) <= 0.03, "power at 12,500 rpm is within 3%% of 28 kW (%.2f kW)" % at_power.kw)
	check(absf(best_kw_rpm - POWER_RPM) < 600.0, "power peak is within 600 rpm of 12,500 (%.0f rpm)" % best_kw_rpm)
	check(absf(at_torque.torque / TORQUE_NM - 1.0) <= 0.05, "torque at 11,000 rpm is within 5%% of 23 N·m (%.2f)" % at_torque.torque)
	check(absf(at_power.kmh / SIXTH_GEAR_KMH_AT_POWER_RPM - 1.0) < 0.02, "gearing only: sixth at 12,500 rpm is 170 km/h (%.1f), road top speed unverified" % at_power.kmh)
	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)


func _hold(sim: EngineSim, spec: EngineSpec, rpm: float) -> Dictionary:
	var dt := sim.physics_dt
	var sum_t := 0.0
	var sum_r := 0.0
	var n := 0
	var revs := 0.0
	sim.running = true
	while revs < 16.0:
		sim.omega = rpm * TAU / 60.0
		sim.rpm = rpm
		sim.step(dt, spec, 1.0, true, false, true, false, 1.0)
		revs += rpm * dt / 60.0
		if revs > 8.0:
			sum_t += sim.torque
			sum_r += sim.rpm
			n += 1
	return {"torque": sum_t / n, "rpm": sum_r / n}


func _kmh(spec: EngineSpec, rpm: float, gear: int) -> float:
	var ratio: float = spec.primary_ratio * float(spec.gear_ratios[gear - 1]) * spec.final_drive
	return rpm * TAU / 60.0 / ratio * EngineSim.tire_radius_m(spec) * 3.6
