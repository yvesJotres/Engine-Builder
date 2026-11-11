extends SceneTree

const CAR_MODEL := preload("res://assets/3d/generated/drivetrain/car_model.gd")
var _fails := 0

func _init() -> void:
	await process_frame
	var data: Dictionary = Presets.PRESETS["bugatti_centodieci"]
	var spec := EngineSpec.new()
	for key in data:
		spec.set(key, data[key])
	var car = CAR_MODEL.new()
	root.add_child(car)
	car.build(spec, Ground.Y)
	check(car._wheels.size() == 4, "car has four wheels")
	check(absf(car.front_axle.z - car.rear_axle.z - 27.11) < 0.001, "wheelbase matches published dimensions")
	check(car.has_node("Body") and car.has_node("Canopy"), "car has body and canopy")
	car.update(60.0, 0.25)
	for wheel_index in car._wheels.size():
		var expected := PI / 2.0 * spec.wheel_radius_m / (spec.wheel_radius_m if wheel_index % 2 == 0 else spec.front_wheel_radius_m)
		check(absf(car._wheels[wheel_index].rotation.x - expected) < 0.001, "wheel rotates according to its radius")
	car.free()
	var library = EngineLibrary.get_instance()
	library._library = Presets.PRESETS
	library._ready = true
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main._panel._on_library_ready(Presets.PRESETS)
	var index := Presets.names().find("bugatti_centodieci")
	main._panel._on_preset_selected(index)
	check(main.spec.vehicle_type == "car" and main.spec.layout == "W", "selecting the preset activates car and W16 mode")
	check(main._car.visible and not main._drivetrain.visible, "car mode replaces motorcycle visuals")
	check(main._car._wheels.size() == 4, "selected car has four wheels")
	check(main._sim.fuel.capacity_litres == 100.0, "selected car has a 100-litre fuel tank")
	check(main._sim.gear.gear_ratios.size() == 7, "selected car has seven forward ratios")
	for frame in 180:
		main._sim.step(1.0 / 60.0, main.spec, 0.0, true, frame < 60, false, false, 1.0)
	check(main._sim.cylinders.size() == 16 and is_finite(main._sim.rpm), "W16 physics steps with finite RPM")
	check(main._sim.running, "W16 starts and continues running")
	print("W16 idle: %.0f rpm, manifold %.1f kPa" % [main._sim.rpm, main._sim.intake.pressure / 1000.0])
	var torque_sum := 0.0
	var minimum_rpm := INF
	var maximum_rpm := 0.0
	var limiter_frames := 0
	for frame in 120:
		main._sim.step(1.0 / 60.0, main.spec, 1.0, true, false, false, false, 1.0)
		torque_sum += main._sim.torque
		minimum_rpm = minf(minimum_rpm, main._sim.rpm)
		maximum_rpm = maxf(maximum_rpm, main._sim.rpm)
		if main._sim.limiter_active:
			limiter_frames += 1
	print("W16 throttle: %.0f-%.0f rpm, %.2f bar absolute, frame-sampled torque %.1f N-m, limiter %d/120 frames" % [minimum_rpm, maximum_rpm, main._sim.intake.pressure / 100000.0, torque_sum / 120.0, limiter_frames])
	check(is_finite(main._sim.rpm) and is_finite(main._sim.intake.pressure), "W16 remains numerically stable under throttle")
	check(main._sim.intake.boost_ratio > 1.0, "W16 turbo approximation spools under throttle")
	check(maximum_rpm <= main.spec.redline_rpm * 1.05, "W16 limiter constrains engine speed")
	for frame in 180:
		main._sim.step(1.0 / 60.0, main.spec, 0.0, true, false, false, false, 1.0)
	print("W16 after throttle release: %.0f rpm, running=%s" % [main._sim.rpm, main._sim.running])
	check(main._sim.running, "W16 remains running after throttle release")
	main._shift(true)
	main._touch_throttle = 1.0
	for frame in 120:
		main._process(1.0 / 60.0)
	print("W16 launch after 2 seconds: %.1f km/h, %.0f rpm, gear %s" % [main._sim.speed * 3.6, main._sim.rpm, main._sim.gear.label()])
	check(main._sim.speed > 0.1 and main._sim.running, "car launches without stalling")
	main._touch_throttle = 0.0
	var bike := Presets.names().find("honda_cbr150r")
	main._panel._on_preset_selected(bike)
	check(not main._car.visible and main._drivetrain.visible, "switching back restores motorcycle visuals")
	check(main._sim.fuel.capacity_litres == 12.0, "switching back restores motorcycle tank capacity")
	main.free()
	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)

func check(ok: bool, message: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + message)
