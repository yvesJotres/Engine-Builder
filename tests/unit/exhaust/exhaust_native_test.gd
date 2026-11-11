extends SceneTree

# The native ExhaustNative (gdextension/src/exhaust_native.cpp) must match scripts/exhaust/exhaust_gas.gd step for step.
# Both get the same layout and the same half-sine valve forcing per cylinder; tail flow, port pressures and the audio samples
# are compared every step. Run: godot --headless --path . -s tests/unit/exhaust/exhaust_native_test.gd
const PRESETS := ["honda_cbr150r", "yamaha_yzf_r1m"]
const DT := 1.0 / 3600.0
const STEPS := 1800 # 0.5 s
const REL_TOL := 1.0e-5
const ABS_FLOOR := 1.0e-6
const MAX_SAMPLES := 88200 # the GDScript ring buffer is only trustworthy before it wraps
const CYCLE_S := 0.04 # one 4-stroke cycle, 3000 rpm
const MDOT_PEAK := 0.02
const POWER_PER_MDOT := 6.0e5

var failures := 0


func _init() -> void:
	await process_frame
	if not ClassDB.class_exists("ExhaustNative"):
		print("SKIP: ExhaustNative is not loaded")
		quit(2)
		return
	for preset in PRESETS:
		_compare(preset)
	print("exhaust_native_test: %s" % ("PASSED" if failures == 0 else "FAILED (%d problems)" % failures))
	quit(0 if failures == 0 else 1)


func _close(a: float, b: float) -> bool:
	return absf(a - b) <= ABS_FLOOR + REL_TOL * maxf(absf(a), absf(b))


func _layout_dict(layout: ExhaustLayout) -> Dictionary:
	var pipes := []
	for p in layout.pipes:
		var radii := PackedFloat64Array() # the layout stores radii as float32; the native wrapper takes float64
		for r in p.radii:
			radii.append(r)
		pipes.append({"pts": p.pts, "radii": radii, "cyl": p.cyl,
				"feeders": PackedInt32Array(p.feeders), "loss": p.loss})
	return {"scene_per_m": ExhaustLayout.M, "pipes": pipes}


func _fail(preset: String, step: int, what: String, a: float, b: float) -> void:
	print("FAIL %s step %d: %s gd=%s native=%s" % [preset, step, what, a, b])
	failures += 1


func _compare(preset: String) -> void:
	var spec := EngineSpec.new()
	var p: Dictionary = Presets.PRESETS[preset]
	for key in p.keys():
		spec.set(key, p[key])
	var layout := ExhaustLayout.build(spec)
	var gd := ExhaustGas.new()
	gd.build(layout)
	var nat: Object = ClassDB.instantiate("ExhaustNative")
	nat.build(_layout_dict(layout))
	var n := spec.cylinders
	var taken := 0
	for s in STEPS:
		var t := s * DT
		for c in n:
			# even firing: cylinder c opens its exhaust for a quarter of the cycle, offset by c/n of the cycle
			var ph := fposmod(t / CYCLE_S - float(c) / n, 1.0)
			var mdot := MDOT_PEAK * sin(ph / 0.25 * PI) if ph < 0.25 else 0.0
			gd.apply_valve(c, mdot, mdot * POWER_PER_MDOT)
			nat.apply_valve(c, mdot, mdot * POWER_PER_MDOT)
		gd.advance(DT)
		nat.advance(DT)
		if not _close(gd.tail_volume_flow(), nat.tail_volume_flow()):
			_fail(preset, s, "tail_volume_flow", gd.tail_volume_flow(), nat.tail_volume_flow())
			return
		for c in n:
			if not _close(gd.port_pressure(c), nat.port_pressure(c)):
				_fail(preset, s, "port_pressure[%d]" % c, gd.port_pressure(c), nat.port_pressure(c))
				return
		var a := gd.take_flow()
		var b: PackedFloat32Array = nat.take_flow()
		if a.size() != b.size():
			_fail(preset, s, "take_flow size", a.size(), b.size())
			return
		for i in a.size():
			if taken >= MAX_SAMPLES:
				break
			taken += 1
			if not _close(a[i], b[i]):
				_fail(preset, s, "take_flow[%d]" % i, a[i], b[i])
				return
	print("%s: %d steps, %d samples compared" % [preset, STEPS, taken])
