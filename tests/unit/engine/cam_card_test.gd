extends SceneTree

# The cam-card lobe matches the MGI calculator: duration at 0.050 inch, lobe separation, advance.
# Card: intake 242, exhaust 254, LSA 118, advance 8, lifts 0.567 and 0.576 inch.
# Run: godot --headless -s tests/unit/engine/cam_card_test.gd

var _fails := 0


func check(ok: bool, msg: String) -> void:
	print(("ok   " if ok else "FAIL ") + msg)
	if not ok:
		_fails += 1


func _card() -> EngineSpec:
	var spec := EngineSpec.new()
	spec.cam_lobe_profile = EngineSpec.CamLobeProfile.CAM_CARD
	spec.intake_lobe_profile = EngineSpec.CamLobeProfile.CAM_CARD
	spec.exhaust_lobe_profile = EngineSpec.CamLobeProfile.CAM_CARD
	spec.intake_duration_deg = 242.0 * Cylinder.SEAT_OVER_050
	spec.exhaust_duration_deg = 254.0 * Cylinder.SEAT_OVER_050
	spec.intake_duration_050_deg = 242.0
	spec.exhaust_duration_050_deg = 254.0
	spec.intake_centre_deg = 360.0 + (118.0 - 8.0)
	spec.exhaust_centre_deg = 360.0 - (118.0 + 8.0)
	spec.intake_lift_mm = 0.567 * 25.4
	spec.exhaust_lift_mm = 0.576 * 25.4
	return spec


func _init() -> void:
	var spec := _card()
	check(spec.validation_warning() == "", "the sample card passes validation (%s)" % spec.validation_warning())
	# Events at 0.050 inch, in the calculator's crank positions.
	check(absf(spec.intake_centre_deg - 360.0 - 110.0) < 0.1, "intake centerline is 110 ATDC")
	check(absf((360.0 - spec.exhaust_centre_deg) - 126.0) < 0.1, "exhaust centerline is 126 BTDC")
	check(absf((360.0 - spec.intake_050_open_deg()) - 11.0) < 0.6, "intake opens 11 BTDC at 0.050 inch (%.1f)" % (360.0 - spec.intake_050_open_deg()))
	check(absf((spec.intake_050_close_deg() - 360.0 - 180.0) - 51.0) < 0.6, "intake closes 51 ABDC at 0.050 inch")
	check(absf(absf(spec.exhaust_050_open_deg() - 360.0 + 180.0) - 73.0) < 0.6, "exhaust opens 73 BBDC at 0.050 inch (%.1f)" % absf(spec.exhaust_050_open_deg() - 360.0 + 180.0))
	check(absf(spec.exhaust_050_close_deg() - 360.0 - 1.0) < 0.6, "exhaust closes 1 ATDC at 0.050 inch (%.1f)" % (spec.exhaust_050_close_deg() - 360.0))
	var overlap := spec.exhaust_050_close_deg() - spec.intake_050_open_deg()
	check(absf(overlap - 12.0) < 0.6, "overlap at 0.050 inch is 12 degrees (%.1f)" % overlap)
	var peak := Cylinder.valve_lift(spec, true, spec.intake_centre_deg)
	check(absf(peak * 1000.0 - spec.intake_lift_mm) < 0.05, "the intake lobe peaks at the stated lift (%.2f mm)" % (peak * 1000.0))
	var at_check := Cylinder.valve_lift(spec, true, spec.intake_050_open_deg())
	check(absf(at_check - Cylinder.CHECK_LIFT_M) < 0.00005, "lift at the 0.050 inch point is 0.050 inch (%.3f mm)" % (at_check * 1000.0))
	var at_seat := Cylinder.valve_lift(spec, true, spec.intake_open_deg())
	check(at_seat < 0.00005, "the seat is shut")
	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
