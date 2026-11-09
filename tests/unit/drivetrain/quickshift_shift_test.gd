extends SceneTree

# A quickshifter upshift at full throttle must change gear with the clutch engaged, and the same shift must not happen
# without the quickshifter. Exits 1 if a check fails. Run: godot --headless --path . -s tests/unit/drivetrain/quickshift_shift_test.gd
func _init() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 60:
		await process_frame

	var with_qs := _upshift(main, true)
	var without_qs := _upshift(main, false)
	print("gear after quickshift up: with QS %d, without QS %d" % [with_qs, without_qs])
	var ok := with_qs == 2 and without_qs == 1
	print("quickshift_shift_test: %s" % ("PASSED" if ok else "FAILED"))
	quit(0 if ok else 1)


# Sets up a full-throttle upshift from first gear with the clutch engaged, returns the gear afterwards
func _upshift(main: Node, quickshifter: bool) -> int:
	main.spec.gear_ratios = [6.362, 4.918, 3.934, 3.152, 2.530, 2.136] # the CBR250RR's gearbox, as the game sets it
	main._sim.gear.gear_ratios = main.spec.gear_ratios
	main.spec.quickshifter = quickshifter
	main.spec.quickshifter_min_rpm = 3000.0
	main._sim.gear.gear = 1
	main._sim.rpm = 7000.0
	main._sim.speed = 20.0 # moving: from a stop, first-gear upshifts go to neutral, not second
	main._sim.clutch_engage = 1.0
	main._throttle = 1.0
	main._pending_shift = 0
	main._shift(true)
	main._update_shift_request(0.0)
	return main._sim.gear.gear
