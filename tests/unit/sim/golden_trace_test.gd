extends SceneTree

# Golden trace gate for the C++ physics migration. The native EngineSimCore must reproduce this
# GDScript reference trace before it becomes the production path.
# Run: godot --headless --path . -s tests/unit/sim/golden_trace_test.gd

const PRESETS := ["honda_cbr150r", "kawasaki_zx25r", "yamaha_yzf_r1m"]
const FIXTURE := "res://tests/fixtures/sim_golden_trace.json"
const FIELDS := ["rpm", "torque", "speed", "fuel", "clutch", "intake_pa", "coolant_c", "oil_c"]

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


func trace(id: String) -> Array:
	var spec := spec_of(id)
	var sim := EngineSim.new()
	sim.physics_dt = 1.0 / 1200.0
	var rows := []
	for i in 240:
		sim.step(1.0 / 60.0, spec, 0.0, true, true, true, false, 1.0)
	for i in 108:
		sim.step(1.0 / 60.0, spec, 0.0, true, false, true, false, 1.0)
	for i in 72:
		sim.step(1.0 / 60.0, spec, 1.0, true, false, true, false, 1.0)
	for i in 36:
		sim.step(1.0 / 60.0, spec, 0.0, true, false, true, false, 1.0)
		rows.append({
			"i": i,
			"rpm": sim.rpm,
			"torque": sim.torque,
			"speed": sim.speed,
			"fuel": sim.fuel_flow,
			"running": sim.running,
			"clutch": sim.clutch_engage,
			"intake_pa": sim.intake.pressure,
			"coolant_c": sim.coolant_c,
			"oil_c": sim.oil_c,
		})
	return rows


func close(a: float, b: float) -> bool:
	return absf(a - b) <= 1e-6 * maxf(1.0, maxf(absf(a), absf(b)))


func _init() -> void:
	var text := FileAccess.get_file_as_string(FIXTURE)
	check(text != "", "golden fixture is missing: " + FIXTURE)
	if text == "":
		quit(1)
		return
	var expected: Dictionary = JSON.parse_string(text)
	for id in PRESETS:
		check(expected.has(id), "golden fixture has no trace for " + id)
		if not expected.has(id):
			continue
		var got := trace(id)
		var want: Array = expected[id]
		check(got.size() == want.size(), "%s trace length changed" % id)
		var n := mini(got.size(), want.size())
		for i in n:
			for field in FIELDS:
				check(close(float(got[i][field]), float(want[i][field])),
					"%s row %d field %s: %.9f vs %.9f" % [id, i, field, got[i][field], want[i][field]])
			check(bool(got[i]["running"]) == bool(want[i]["running"]),
				"%s row %d running state changed" % [id, i])
			if _fails > 20:
				break
		if _fails > 20:
			break
	print("golden_trace_test: %s" % ("PASSED" if _fails == 0 else "FAILED"))
	quit(0 if _fails == 0 else 1)