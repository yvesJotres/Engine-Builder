extends SceneTree

# A downshift request is not a throttle blip. The blip is the quickshifter's rev match for a clutch-less drop into
# a lower gear: clicking down into first from neutral, or shifting with the clutch pulled in, must leave the engine
# alone. It used to blip on every downshift request, so neutral into first raced the engine with the clutch open.
# Run: godot --headless --path . -s tests/unit/drivetrain/downshift_blip_test.gd (prints PASS or FAIL)

var _fails := 0
var _main
var _sim
var _spec


func _init() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	await process_frame
	_main.set_process(false)
	_sim = _main._sim
	_spec = _main.spec
	# The app opens on whatever engine was last used; pin a manual bike with a quickshifter fitted and switched on.
	_spec.vehicle_type = "motorcycle"
	_spec.transmission_type = "manual"
	_spec.has_quickshifter = true
	_spec.quickshifter = true
	_sim.gear.gear_ratios = _spec.gear_ratios

	# 1. Neutral into first with the clutch pulled in: the gear is selected, the engine is left alone.
	_clutch_pulled(true)
	_sim.gear.gear = 0
	_sim.speed = 0.0
	_main._throttle = 0.0
	_main._shift(false)
	check(_sim.gear.gear == 1, "a click down from neutral selects first")
	check(not _blips(), "neutral into first with the clutch pulled in does not blip (the engine must not race)")

	# 2. Rolling into first from neutral with the clutch out: still no gear dropped, so still no blip.
	_clutch_pulled(false)
	_sim.gear.gear = 0
	_sim.speed = _speed_for_gear_rpm(1, 6000.0)
	_sim.rpm = 6000.0
	_sim.gearbox_load = 0.0
	_main._throttle = 0.0
	_main._shift(false)
	check(_sim.gear.gear == 1, "a click down from neutral rolling selects first")
	check(not _blips(), "neutral into first with the clutch out does not blip")

	# 3. The touch SHIFT - pad takes the same route, so it must not blip into first either.
	_sim.gear.gear = 0
	_sim.speed = 0.0
	_clutch_pulled(true)
	_main._touch.shift_pressed.emit(false)
	check(_sim.gear.gear == 1, "the touch SHIFT - pad selects first from neutral")
	check(not _blips(), "the touch SHIFT - pad into first does not blip")

	# 4. A clutch-less drop into a lower gear is a real quickshift: the gear drops and the rev match blips.
	_clutch_pulled(false)
	_clear_blip()
	_sim.gear.gear = 3
	_sim.speed = _speed_for_gear_rpm(2, 6000.0)
	_sim.rpm = 6500.0
	_sim.gearbox_load = 0.0
	_main._throttle = 0.0
	_main._shift(false)
	check(_sim.gear.gear == 2, "a clutch-less downshift drops a gear")
	check(_blips(), "a clutch-less downshift blips the throttle")

	# 5. The same downshift with the clutch pulled in needs no blip: the rider owns the revs.
	_clutch_pulled(true)
	_clear_blip()
	_sim.gear.gear = 3
	_sim.rpm = 6500.0
	_sim.gearbox_load = 0.0
	_main._shift(false)
	check(_sim.gear.gear == 2, "a downshift with the clutch pulled in drops a gear")
	check(not _blips(), "a downshift with the clutch pulled in does not blip")

	# 6. An upshift never blips.
	_clutch_pulled(false)
	_clear_blip()
	_sim.gear.gear = 2
	_sim.speed = _speed_for_gear_rpm(3, 7000.0)
	_sim.rpm = 7000.0
	_main._throttle = 1.0
	_main._shift(true)
	check(_sim.gear.gear == 3, "a clutch-less upshift selects third")
	check(not _blips(), "an upshift does not blip")

	# 7. A bike with the quickshifter switched off still changes down by hand, without a blip.
	_clear_blip()
	_spec.quickshifter = false
	_sim.gear.gear = 3
	_sim.speed = _speed_for_gear_rpm(2, 6000.0)
	_sim.rpm = 6000.0
	_sim.gearbox_load = 0.0
	_main._throttle = 0.0
	_main._shift(false)
	check(_sim.gear.gear == 2, "a downshift with the quickshifter off still drops a gear")
	check(not _blips(), "a downshift with the quickshifter off does not blip")
	_spec.quickshifter = true

	_main.free()
	print("RESULT: " + ("PASS" if _fails == 0 else "FAIL"))
	quit(1 if _fails > 0 else 0)


func _clutch_pulled(pulled: bool) -> void:
	_main._clutch_held = pulled
	_sim.clutch_engage = 0.0 if pulled else 1.0


# What the engine is actually being asked for this step: the blip shows up as a throttle override above zero.
func _blips() -> bool:
	return _sim.ecu.update(0.0, maxf(_sim.rpm, 1000.0), 0.0, true, _spec) > 0.0


# Cancels any cut or blip in flight: the ECU drops its intervention on the step where the quickshifter is off.
func _clear_blip() -> void:
	_spec.quickshifter = false
	_sim.ecu.update(0.0, maxf(_sim.rpm, 1000.0), 0.0, true, _spec)
	_spec.quickshifter = true


# Road speed that puts the given gear at the given engine speed, for a bike of this specification.
func _speed_for_gear_rpm(gear: int, rpm: float) -> float:
	var ratio: float = _spec.primary_ratio * float(_sim.gear.gear_ratios[gear - 1]) * _spec.final_drive
	return rpm * EngineSim.tire_radius_m(_spec) * TAU / (60.0 * ratio)


func check(ok: bool, message: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + message)
