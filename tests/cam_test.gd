extends SceneTree

# Checks the cams: the default cam settings reproduce the stock wide-open torque, and changing the lift or the duration of
# the intake valve changes it. Run: godot --headless -s tests/cam_test.gd (exit code 1 on failure)

const DT := 1.0 / 60.0
var _fails := 0


func check(ok: bool, msg: String) -> void:
	print(("ok   " if ok else "FAIL ") + msg)
	if not ok:
		_fails += 1


# Average gas torque of one cylinder at 7,000 rpm, wide open, with this spec's cams (the same run as test_engine.gd).
func _torque(spec: EngineSpec) -> float:
	var cyl := Cylinder.new()
	cyl.setup(spec.bore_mm, spec.stroke_mm, spec.compression_ratio)
	cyl.set_cams(spec)
	var man := EngineAir.new()
	var tank := FuelTank.new()
	var dphi := 7000.0 * 6.0 * DT
	var ign := 720.0 - EngineAir.spark_advance_deg(7000.0)
	var sum := 0.0
	var n := 0
	for i in 300:
		var r := cyl.advance(dphi, DT, man.pressure, EngineAir.T0, ign, true, tank, 1.0)
		man.manifold_update(DT, 1.0, r.y / DT)
		if i >= 240:
			sum += r.x
			n += 1
	return sum / n


func _init() -> void:
	await process_frame
	var stock := _torque(EngineSpec.new())
	check(absf(stock - 10.63) < 0.05, "default cams give the stock wide-open torque (%.2f N·m, stock 10.63)" % stock)
	var lift := EngineSpec.new()
	lift.intake_lift_mm = 9.0
	var more_lift := _torque(lift)
	check(absf(more_lift - stock) > 0.05, "more intake lift changes the torque (%.2f N·m)" % more_lift)
	var dur := EngineSpec.new()
	dur.intake_duration_deg = 280.0
	var longer := _torque(dur)
	check(absf(longer - stock) > 0.05, "a longer intake duration changes the torque (%.2f N·m)" % longer)
	var bad := EngineSpec.new()
	bad.intake_duration_deg = 400.0
	check(bad.validation_warning() != "", "a duration of 400 deg fails validation: %s" % bad.validation_warning())
	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
