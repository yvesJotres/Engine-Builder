extends SceneTree

func _init() -> void:
	var data: Dictionary = Presets.PRESETS["bugatti_centodieci"]
	var spec := EngineSpec.new()
	for key in data:
		spec.set(key, data[key])
	
	print("=== Bugatti Centodieci Steady-State Dyno ===")
	print("Displacement: %.1f cc, Cylinders: %d, Redline: %.0f rpm" % [spec.displacement_cc, spec.cylinders, spec.redline_rpm])
	print("Primary: %.3f, Final: %.3f, Gears: %s" % [spec.primary_ratio, spec.final_drive, spec.gear_ratios])
	print("")
	
	# Test at multiple RPM points
	var test_rpms := [1500.0, 2500.0, 3500.0, 4500.0, 5500.0, 6500.0, 7500.0]
	
	var peak_torque := 0.0
	var peak_torque_rpm := 0.0
	var peak_hp := 0.0
	var peak_hp_rpm := 0.0
	var peak_pressure := 0.0
	
	for rpm in test_rpms:
		var result := _measure(spec, rpm)
		print("steady %.0f rpm: %.1f N·m, %.1f hp, %.2f bar abs, %.1f °C exhaust" % [rpm, result.torque, result.hp, result.pressure / 100000.0, result.exhaust_temp])
		
		if result.torque > peak_torque:
			peak_torque = result.torque
			peak_torque_rpm = rpm
		if result.hp > peak_hp:
			peak_hp = result.hp
			peak_hp_rpm = rpm
		if result.pressure > peak_pressure:
			peak_pressure = result.pressure
	
	print("")
	print("=== Peak Values ===")
	print("Peak torque: %.1f N·m at %.0f rpm" % [peak_torque, peak_torque_rpm])
	print("Peak power:  %.1f hp at %.0f rpm" % [peak_hp, peak_hp_rpm])
	print("Peak boost:  %.2f bar absolute" % [peak_pressure / 100000.0])
	
	# Calculate top speed in each gear at peak power RPM
	print("")
	print("=== Top Speed by Gear (at %.0f rpm) ===" % peak_hp_rpm)
	for gear_idx in range(spec.gear_ratios.size()):
		var ratio: float = spec.primary_ratio * spec.gear_ratios[gear_idx] * spec.final_drive
		var tire_r: float = EngineSim.tire_radius_m(spec)
		var speed_ms: float = peak_hp_rpm * TAU / 60.0 * tire_r / ratio
		var speed_kmh: float = speed_ms * 3.6
		var speed_mph: float = speed_kmh * 0.621371
		print("Gear %d (%.3f): %.1f km/h (%.1f mph)" % [gear_idx + 1, spec.gear_ratios[gear_idx], speed_kmh, speed_mph])
	
	# Also check redline top speed
	print("")
	print("=== Top Speed by Gear (at %.0f rpm redline) ===" % spec.redline_rpm)
	for gear_idx in range(spec.gear_ratios.size()):
		var ratio: float = spec.primary_ratio * spec.gear_ratios[gear_idx] * spec.final_drive
		var tire_r: float = EngineSim.tire_radius_m(spec)
		var speed_ms: float = spec.redline_rpm * TAU / 60.0 * tire_r / ratio
		var speed_kmh: float = speed_ms * 3.6
		var speed_mph: float = speed_kmh * 0.621371
		print("Gear %d (%.3f): %.1f km/h (%.1f mph)" % [gear_idx + 1, spec.gear_ratios[gear_idx], speed_kmh, speed_mph])
	
	# Check if values are finite
	if not is_finite(peak_torque) or not is_finite(peak_hp):
		print("RESULT: FAIL - Non-finite values")
		quit(1)
	
	print("RESULT: PASS")
	quit()

func _measure(spec: EngineSpec, target_rpm: float) -> Dictionary:
	var sim := EngineSim.new()
	sim.audio_enabled = false
	sim.fuel.set_kind(spec.fuel)
	sim.running = true
	var torque_sum := 0.0
	var exhaust_temp_sum := 0.0
	var samples := 0
	var step := 1.0 / 3600.0
	for index in 10800:
		sim.rpm = target_rpm
		sim.omega = target_rpm * TAU / 60.0
		sim.step(step, spec, 1.0, true, false, true, false, 1.0)
		if index >= 7200:
			torque_sum += sim.torque
			exhaust_temp_sum += sim.exhaust_temp_c()
			samples += 1
	var torque := torque_sum / samples
	var avg_exhaust_temp := exhaust_temp_sum / samples
	return {
		"torque": torque, 
		"hp": Units.w_to_hp(Units.power_w(torque, target_rpm)), 
		"pressure": sim.intake.pressure,
		"exhaust_temp": avg_exhaust_temp
	}