extends SceneTree

# Compression ratio, both kinds. The number in the preset is the GEOMETRIC ratio - (swept + clearance) / clearance - and
# this checks that the clearance the simulation builds really gives it, for every bundled preset. The EFFECTIVE ratio is
# what the charge sees: the volume when the intake valve shuts over the clearance volume, which a long-duration cam
# makes smaller. Both are now read off the cylinder rather than assumed.
# Run: godot --headless --path . -s res://tests/unit/engine/compression_ratio_test.gd   (prints PASS or FAIL)

const DT := 1.0 / 60.0

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func _spec(id: String) -> EngineSpec:
	var spec := EngineSpec.new()
	for key in Presets.PRESETS[id].keys():
		spec.set(key, Presets.PRESETS[id][key])
	return spec


func _init() -> void:
	await process_frame

	# ---- every preset: the clearance the sim builds gives back the ratio in the data ----
	var worst := 0.0
	var worst_id := ""
	var n := 0
	for id in Presets.PRESETS.keys():
		var spec := _spec(id)
		var c := Cylinder.new()
		if spec.stroke_type == "two_stroke":
			var t := TwoStrokeCylinder.new()
			t.setup(spec)
			worst = maxf(worst, absf(t.compression_ratio_geometric() - spec.compression_ratio))
			worst_id = id if absf(t.compression_ratio_geometric() - spec.compression_ratio) >= worst else worst_id
		else:
			c.setup(spec.bore_mm, spec.stroke_mm, spec.compression_ratio, spec.reciprocating_kg(), spec.rod_over_crank_radius())
			var err := absf(c.compression_ratio_geometric() - spec.compression_ratio)
			if err >= worst:
				worst = err
				worst_id = id
		n += 1
	print("%d presets: worst geometric ratio error %.9f (%s)" % [n, worst, worst_id])
	check(worst < 1.0e-6, "the built clearance gives the preset's ratio (worst %.9f on %s)" % [worst, worst_id])

	# ---- a running engine: the charge is compressed less than the geometry says ----
	var spec: EngineSpec = _spec("kawasaki_zx25r_se")
	var sim := EngineSim.new()
	sim.fuel.set_kind(spec.fuel)
	for i in 240:
		sim.step(DT, spec, 0.3, true, i < 60, false, false, 1.0)
	var geo: float = sim.compression_ratio_geometric()
	var eff: float = sim.compression_ratio_effective()
	print("ZX-25R SE at %.0f rpm: geometric %.2f:1, effective %.2f:1 (%.1f%% of it)"
		% [sim.rpm, geo, eff, 100.0 * eff / geo])
	check(absf(geo - spec.compression_ratio) < 1.0e-6, "the running engine's geometric ratio is the preset's")
	check(eff < geo, "the effective ratio is below the geometric one (late intake closing)")
	# an intake closing around 50 deg ABDC throws about 15 % of the swept volume back out on this engine; anything under
	# 80 % of the geometric ratio would mean the closing angle or the volume model is wrong, not that the cam is long
	check(eff > geo * 0.80, "and not absurdly below it (%.2f:1)" % eff)

	# ---- a later intake closing lowers it, as a longer cam should ----
	var early := Cylinder.new()
	early.setup(50.0, 31.8, 11.5, 0.09, 2.0)
	early.intake_close = 530.0
	var late := Cylinder.new()
	late.setup(50.0, 31.8, 11.5, 0.09, 2.0)
	late.intake_close = 620.0
	var tank := FuelTank.new()
	tank.set_kind("ron95")
	for i in 72 * 8:
		early.advance(10.0, 10.0 / (6.0 * 6000.0), 101325.0, 300.0, -15.0, true, tank, 1.0)
		late.advance(10.0, 10.0 / (6.0 * 6000.0), 101325.0, 300.0, -15.0, true, tank, 1.0)
	print("intake close 530 deg: effective %.2f:1 ; 620 deg: %.2f:1" % [early.compression_ratio_effective(), late.compression_ratio_effective()])
	check(late.compression_ratio_effective() < early.compression_ratio_effective(),
		"closing the intake later lowers the effective ratio (%.2f vs %.2f)" % [late.compression_ratio_effective(), early.compression_ratio_effective()])
	check(absf(early.compression_ratio_geometric() - late.compression_ratio_geometric()) < 1.0e-9,
		"the cam does not change the geometric ratio")

	if _fails == 0:
		print("compression_ratio_test: PASS (geometric honoured for every preset, effective read from intake closing)")
	quit(0 if _fails == 0 else 1)
