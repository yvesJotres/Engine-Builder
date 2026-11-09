extends SceneTree

func _init() -> void:
	var bike := Drivetrain.new()
	root.add_child(bike)
	bike.build(0.0, Vector3(0, 2, 0), Vector3(0, 4, 0))
	var controls := bike.get_node("FootControls")
	assert(controls.has_node("Footpeg1") and controls.has_node("Footpeg-1"))
	assert(controls.has_node("ShiftPedal") and controls.has_node("RearBrakePedal"))
	var pedal := controls.get_node("RearBrakePedal") as Node3D
	bike.update(0.0, 0.0, 0.016, 0.0)
	assert(is_zero_approx(pedal.rotation.x))
	bike.update(0.0, 0.0, 0.016, 1.0)
	assert(pedal.rotation.x > 0.0)
	var shifter := controls.get_node("ShiftPedal") as Node3D
	bike.animate_shift(true)
	assert(shifter.rotation.x < 0.0)
	bike.update(0.0, 0.0, 1.0, 0.0)
	assert(is_zero_approx(shifter.rotation.x) and is_zero_approx(pedal.rotation.x))
	bike.animate_shift(false)
	assert(shifter.rotation.x > 0.0)
	var dyno := DynoTest.new()
	dyno.shift_pedal_requested.connect(bike.animate_shift)
	var gearbox := Gearbox.new()
	gearbox.gear = 1
	dyno._shift_up_one_gear(gearbox)
	assert(gearbox.gear == 2 and shifter.rotation.x < 0.0)
	dyno._step_toward_first(gearbox)
	assert(gearbox.gear == 1 and shifter.rotation.x > 0.0)
	print("foot controls: PASS")
	quit()
