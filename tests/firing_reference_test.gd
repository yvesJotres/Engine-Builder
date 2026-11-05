extends SceneTree

# Each preset's firing angles must match the ignition wiring of its engine-sim reference file, cylinder by cylinder,
# and the firing sequence must match the reference's order in time. Run: godot --headless -s tests/firing_reference_test.gd
# (exit code 1 on failure)

# preset name -> [reference file, expected wire angle per cylinder, expected firing order (1-based cylinder numbers)]
const EXPECTED := {
	"Honda CBR150R (K45N)": ["honda/cbr150.mr", [0.0], [1]],
	"Honda CBR250RR (2017, MC51)": ["honda/cbr250rr.mr", [0.0, 180.0], [1, 2]],
	"Kawasaki ZX-25R (2020)": ["kawasaki/zx_25r.mr", [0.0, 180.0, 540.0, 360.0], [1, 2, 4, 3]],
	"Yamaha YZF-R1M (2015)": ["yamaha/yzf_r1.mr", [0.0, 450.0, 270.0, 540.0], [1, 3, 2, 4]],
	"Honda TRX520 (engine-sim)": ["atg-video-1/01_honda_trx520.mr", [0.0], [1]],
	"Ducati Panigale V4 (1,103 cc)": ["ducati/panigale_v4.mr", [0.0, 630.0, 480.0, 390.0], [1, 4, 3, 2]],
}

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func _init() -> void:
	await process_frame
	for name in EXPECTED:
		var spec := EngineSpec.new()
		var preset: Dictionary = Presets.PRESETS[name]
		for key in preset:
			spec.set(key, preset[key])
		var expected: Array = EXPECTED[name][1]
		var order: Array = EXPECTED[name][2]
		var fire := FiringOrders.for_spec(spec)
		check(fire.size() == spec.cylinders, "%s: %d firing angles for %d cylinders" % [name, fire.size(), spec.cylinders])
		for i in mini(fire.size(), expected.size()):
			check(absf(fire[i] - expected[i]) < 0.01, "%s: cylinder %d fires at %.0f, reference %s wires %.0f" % [name, i + 1, fire[i], EXPECTED[name][0], expected[i]])
		# the sequence in time: cylinders sorted by firing angle, starting from the cylinder that fires first
		var by_time := []
		for i in fire.size():
			by_time.append([fire[i], i + 1])
		by_time.sort_custom(func(a, b): return a[0] < b[0])
		var seq := []
		for pair in by_time:
			seq.append(pair[1])
		check(seq == order, "%s: firing order %s, reference %s" % [name, str(seq), str(order)])
		print("%s: %s" % [name, str(seq)])
	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
