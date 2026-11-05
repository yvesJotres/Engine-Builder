extends SceneTree

# Automatic drive cycle on one preset: start, rev bomb, rev test, launch and shift to top speed, then brake to a stop.
# Run with: godot --headless --path . -s tools/diagnostics/drive_cycle.gd

const DT := 1.0 / 120.0

var spec := EngineSpec.new()
var sim := EngineSim.new()


func _init() -> void:
	for name in Presets.PRESETS.keys():
		spec = EngineSpec.new()
		sim = EngineSim.new()
		_cycle(name)
	quit()


func _cycle(name: String) -> void:
	var p: Dictionary = Presets.PRESETS[name]
	spec.cylinders = p.cylinders
	spec.bore_mm = p.bore_mm
	spec.stroke_mm = p.stroke_mm
	spec.displacement_cc = Units.displacement_cc(spec.bore_mm, spec.stroke_mm, spec.cylinders)
	spec.twin_pin_deg = p.get("twin_pin_deg", 360.0)
	spec.crossplane = p.get("crossplane", false)
	spec.rod_ratio = p.rod_ratio
	spec.compression_ratio = p.get("compression_ratio", 11.3)
	spec.vehicle_kg = p.get("vehicle_kg", 215.0)
	spec.redline_rpm = p.redline_rpm
	spec.flywheel_kg = p.flywheel_kg
	spec.flywheel_radius_mm = p.flywheel_radius_mm
	spec.primary_ratio = p.get("primary_ratio", 3.26)
	spec.final_drive = p.get("final_drive", 3.0)
	spec.gear_ratios = p.get("gear_ratios", Gearbox.ratios())
	spec.header = p.header
	spec.fuel = p.fuel
	sim.fuel.set_kind(spec.fuel)

	print("== %s, redline %d rpm ==" % [name, spec.redline_rpm])

	# 1. start in neutral and let it idle
	_run(8.0, 0.0, true, true, false, false)
	print("start: running=%s, idle %.0f rpm" % [sim.running, sim.rpm])

	# 2. rev bomb: snap the throttle open and shut, twice
	for i in 2:
		var peak := _run(0.6, 1.0, true, false, false, false)
		print("rev bomb %d: peak %.0f rpm" % [i + 1, peak])
		_run(1.5, 0.0, true, false, false, false)

	# 3. rev test in neutral: wide open to the limiter
	var test_peak := _run(4.0, 1.0, true, false, false, false)
	print("rev test in neutral: peak %.0f rpm (redline %d)" % [test_peak, spec.redline_rpm])
	_run(2.0, 0.0, true, false, false, false)

	# 4. launch in first, shift up at 92% of redline, hold top gear until the speed levels off
	_shift(false, 0.3) # down from neutral is 1st, with a little throttle as the clutch comes in
	var top_speed := 0.0
	var elapsed := 0.0
	while elapsed < 90.0:
		_step(1.0, false)
		# shift at 92% of redline, or at 80% once the speed has stopped gaining over 2 s (the bike is power-limited in this gear)
		_check_time += DT
		var stalled := false
		if _check_time >= 2.0:
			stalled = sim.speed - _check_speed < 0.28
			_check_speed = sim.speed
			_check_time = 0.0
		if sim.gear.gear < spec.gear_ratios.size() and sim.clutch_engage >= 0.999 and (sim.rpm >= spec.redline_rpm * 0.92 or (stalled and sim.rpm >= spec.redline_rpm * 0.8)):
			_shift(true)
			_check_speed = sim.speed
			_check_time = 0.0
			print("  shift up to %d at %.1f km/h, %.0f rpm" % [sim.gear.gear, sim.speed * 3.6, sim.rpm])
		top_speed = maxf(top_speed, sim.speed)
		elapsed += DT
		if sim.gear.gear == spec.gear_ratios.size() and _speed_levelled():
			break
	print("top speed %.1f km/h at %.0f rpm in gear %d" % [top_speed * 3.6, sim.rpm, sim.gear.gear])

	# 5. slow down: close the throttle and brake to a stop
	var brake_t := 0.0
	while sim.speed > 0.1 and brake_t < 30.0:
		_step(0.0, true)
		brake_t += DT
	print("brake from %.1f km/h to stop in %.1f s, engine %.0f rpm" % [top_speed * 3.6, brake_t, sim.rpm])


# Runs for seconds with fixed inputs. Returns the highest rpm seen.
func _run(seconds: float, throttle: float, ignition: bool, starter: bool, clutch: bool, brake: bool) -> float:
	var peak := 0.0
	for i in int(seconds / DT):
		sim.step(DT, spec, throttle, ignition, starter and not sim.running, clutch, brake, 1.0)
		peak = maxf(peak, sim.rpm)
	return peak


# One step with the throttle open and the clutch engaged, or the brake on.
func _step(throttle: float, brake: bool) -> void:
	sim.step(DT, spec, throttle, true, false, false, brake, 1.0)


# Pulls the clutch in, changes gear, lets the clutch come back with the given throttle.
func _shift(up: bool, release_throttle := 0.0) -> void:
	_run(0.4, 0.0, true, false, true, false)
	if up:
		sim.gear.shift_up()
		if sim.gear.gear == 0:
			sim.gear.shift_up() # 1st to 2nd passes through neutral, as one stroke of the lever
	else:
		sim.gear.shift_down()
	_run(0.2, release_throttle, true, false, false, false)


var _last_speed := -1.0
var _steady := 0.0
var _check_speed := 0.0
var _check_time := 0.0


# True once the bike's speed has stopped changing for 3 seconds.
func _speed_levelled() -> bool:
	if absf(sim.speed - _last_speed) < 0.02:
		_steady += DT
	else:
		_steady = 0.0
	_last_speed = sim.speed
	return _steady > 3.0
