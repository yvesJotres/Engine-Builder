extends SceneTree

# Per-engine exhaust bodies: finite, deterministic, distinct for the three example engines, cacheable, and
# bypassed by an explicit measured IR. Exits 1 on failure.

const PRESETS := ["honda_cbr150r", "kawasaki_zx25r", "yamaha_yzf_r1m"]
const RATE := 44100.0
const BANDS := [80.0, 160.0, 320.0, 640.0, 1280.0, 2560.0, 5120.0]

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func spec_of(id: String) -> EngineSpec:
	var spec := EngineSpec.new()
	var p: Dictionary = Presets.PRESETS[id]
	for key in p.keys():
		spec.set(key, p[key])
	return spec


func build(id: String) -> PackedFloat32Array:
	var spec := spec_of(id)
	var layout := ExhaustLayout.build(spec)
	return EngineSound._load_ir(spec, layout)


func goertzel(x: PackedFloat32Array, hz: float) -> float:
	var coeff := 2.0 * cos(TAU * hz / RATE)
	var s1 := 0.0
	var s2 := 0.0
	for v in x:
		var s: float = v + coeff * s1 - s2
		s2 = s1
		s1 = s
	return s1 * s1 + s2 * s2 - coeff * s1 * s2


func centroid(x: PackedFloat32Array) -> float:
	var total := 0.0
	var weighted := 0.0
	for hz in BANDS:
		var p := goertzel(x, hz)
		total += p
		weighted += hz * p
	return weighted / maxf(total, 1e-12)


func mean_abs(x: PackedFloat32Array) -> float:
	var s := 0.0
	for v in x:
		s += absf(v)
	return s / maxf(float(x.size()), 1.0)


func difference(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var n := mini(a.size(), b.size())
	var s := 0.0
	for i in n:
		s += absf(a[i] - b[i])
	return s / maxf(float(n), 1.0)


func _init() -> void:
	EngineSound.clear_generated_irs()
	var irs := {}
	for id in PRESETS:
		var ir := build(id)
		irs[id] = ir
		check(ir.size() > 1000, "%s body is too short (%d taps)" % [id, ir.size()])
		check(ir.size() <= EngineSound.MAX_TAPS, "%s body exceeds MAX_TAPS (%d)" % [id, ir.size()])
		var peak := 0.0
		var weight := 0.0
		var finite := true
		for v in ir:
			peak = maxf(peak, absf(v))
			weight += absf(v)
			if not is_finite(v):
				finite = false
		check(finite, "%s body has non-finite samples" % id)
		check(peak > 0.0 and peak <= 1.0 + 1e-5, "%s body peak is %f" % [id, peak])
		check(absf(weight - 1.0) <= 1e-4, "%s body sum-abs is %f, not 1" % [id, weight])

	# Determinism: same spec/layout, same body, before and after a cache clear.
	var base := EngineSound._kernel(EngineSound.IR_MUFFLER)
	var spec := spec_of("kawasaki_zx25r")
	var layout := ExhaustLayout.build(spec)
	var a := ExhaustIr.modify(base, spec, layout)
	var b := ExhaustIr.modify(base, spec, layout)
	check(a == b, "same engine geometry produced two different bodies")

	# A measured override must be returned unchanged.
	var override := spec_of("kawasaki_zx25r")
	override.exhaust_ir_path = "res://assets/ir/sharp_01.wav"
	var measured := EngineSound._load_ir(override, ExhaustLayout.build(override))
	check(measured == EngineSound._kernel(override.exhaust_ir_path), "exhaust_ir_path override was modified")

	# Cache: building the same engine twice must not add a second entry.
	EngineSound.clear_generated_irs()
	build("honda_cbr150r")
	var after_first := EngineSound.generated_ir_count()
	build("honda_cbr150r")
	check(EngineSound.generated_ir_count() == after_first, "repeated setup rebuilt the same body")

	# Distinctness: the three example engines must not share the same effective body.
	var reference := mean_abs(irs["honda_cbr150r"])
	for id in ["kawasaki_zx25r", "yamaha_yzf_r1m"]:
		var d := difference(irs["honda_cbr150r"], irs[id])
		check(d > 0.01 * maxf(reference, 0.001), "CBR150R and %s bodies are too similar (%f)" % [id, d])
		var c1 := centroid(irs["honda_cbr150r"])
		var c2 := centroid(irs[id])
		check(absf(c1 - c2) / maxf(c1, 1.0) > 0.05, "CBR150R and %s centroids are too close (%f vs %f)" % [id, c1, c2])

	print("exhaust_ir_test: %s" % ("PASSED" if _fails == 0 else "FAILED"))
	quit(0 if _fails == 0 else 1)