extends SceneTree

# Checks the cams: the default cam settings reproduce the stock wide-open torque, and changing the lift or the duration of
# the intake valve changes it. Run: godot --headless -s tests/unit/engine/cam_test.gd (exit code 1 on failure)

const DT := 1.0 / 60.0
var _fails := 0


func check(ok: bool, msg: String) -> void:
	print(("ok   " if ok else "FAIL ") + msg)
	if not ok:
		_fails += 1


# Average gas torque of one cylinder at 7,000 rpm, wide open, with this spec's cams (the same run as test_engine.gd).
func _torque(spec: EngineSpec, apply_cams: bool = true) -> float:
	var cyl := Cylinder.new()
	cyl.setup(spec.bore_mm, spec.stroke_mm, spec.compression_ratio, spec.reciprocating_kg(), spec.rod_over_crank_radius())
	if apply_cams:
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
	var spec := EngineSpec.new()
	var stock := _torque(spec)
	var built_in := _torque(spec, false)
	# Defaults now use the cam-card lobe; the no-spec cylinder keeps the old half-sine profile.
	# Prove both that the default cam profile is applied and that the legacy profile remains reproducible.
	check(absf(stock - built_in) > 0.005, "default cam-card profile differs from the legacy cylinder cams (%.2f N·m)" % stock)
	var legacy := EngineSpec.new()
	legacy.cam_lobe_profile = EngineSpec.CamLobeProfile.HALF_SINE
	legacy.intake_lobe_profile = EngineSpec.CamLobeProfile.HALF_SINE
	legacy.exhaust_lobe_profile = EngineSpec.CamLobeProfile.HALF_SINE
	check(absf(_torque(legacy) - built_in) < 0.001, "half-sine compatibility cams match the built-in cylinder cams (%.2f N·m)" % built_in)
	var lift := EngineSpec.new()
	lift.intake_lift_mm = 3.0
	var less_lift := _torque(lift)
	check(absf(less_lift - stock) > 0.05, "less intake lift changes the torque (%.2f N·m)" % less_lift)
	var dur := EngineSpec.new()
	dur.intake_duration_deg = 280.0
	var longer := _torque(dur)
	check(absf(longer - stock) > 0.05, "a longer intake duration changes the torque (%.2f N·m)" % longer)
	var bad := EngineSpec.new()
	bad.intake_duration_deg = 400.0
	check(bad.validation_warning() != "", "a duration of 400 deg fails validation: %s" % bad.validation_warning())
	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
