extends SceneTree

# Gap 14 of docs/physics-validation.md: the measured dyno curves were compared by eye, never by a test.
#
# For each bike with a measured curve in assets/dyno/, hold a set of rpm points wide open, take the crank torque, knock
# it down by the driveline efficiency to the rear wheel, and compare with the digitised chart. The curves are rear-wheel
# mechanical hp, digitised by hand with about +-1 hp of reading error, so the tolerance is 5% mean and 10% worst point -
# the band gap 14 asked for - and every point is printed whether it passes or not, because the table is the useful output.
#
# The model's own accuracy ceiling matters here: docs/papers/Qasemian_2020 reports the original Woschni correlation is
# about 13% off in expansion against a measured trace, so a bike that misses by 5% is inside the heat-transfer model's
# quoted error and is not proof of a bug. That is why this gate reports a table instead of a single pass/fail number.
#
# Run: godot --headless --path . -s res://tests/integration/dyno/dyno_regression_test.gd   (exit 1 on failure)

const FILES := [
	"res://assets/dyno/honda_cbr250rr_2020.json",
	"res://assets/dyno/honda_cbr250rr_sp_qs.json",
	"res://assets/dyno/kawasaki_ninja_300.json",
	"res://assets/dyno/honda_cbr1000rrr_sp.json",
	"res://assets/dyno/yamaha_yzf_r1m.json",
]
const MAX_POINTS := 9
const MEAN_TOL := 0.05 # the band gap 14 asked for
const WORST_TOL := 0.10 # one bad point is allowed to be worse; the mean is the gate
const KW_PER_HP := 0.7457

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


# Wide-open torque at a fixed rpm: run past the transient, then average.
# The torque is the mean over the last CLOSED cycle (sim.cycle_brake_torque), not sim.torque: that one is the last
# sub-step's shaft torque, and at high rpm the firing phase swings it through zero and negative (measured: -34 N m at
# 8000 rpm on an engine reading 12 bar BMEP). A dynamometer averages over cycles; so must this.
func _hold(sim: EngineSim, spec: EngineSpec, rpm: float) -> float:
	var dt := sim.physics_dt
	var revs := 0.0
	sim.running = true
	while revs < 16.0:
		sim.omega = rpm * TAU / 60.0
		sim.rpm = rpm
		sim.step(dt, spec, 1.0, true, false, true, false, 1.0)
		revs += rpm * dt / 60.0
	# cycle_brake_torque is the mean shaft torque over the last CLOSED cycle - what a dynamometer reports.
	return sim.cycle_brake_torque


func _points(samples: Array, redline: float) -> Array:
	var usable := []
	for s in samples:
		var rpm := float(s[0])
		var hp := float(s[1])
		# Above the limiter a held rpm is not a dynamometer condition: the sim cuts fuel and makes negative torque,
		# so those samples measure the limiter, not the engine.
		if rpm > 3000.0 and hp > 3.0 and rpm < redline * 0.99:
			usable.append([rpm, hp])
	if usable.size() <= MAX_POINTS:
		return usable
	var out := []
	for i in MAX_POINTS:
		out.append(usable[int(round(float(i) * float(usable.size() - 1) / float(MAX_POINTS - 1)))])
	return out


static func _rear_hp(crank_kw: float) -> float:
	return crank_kw / KW_PER_HP * EngineSim.DRIVE_EFFICIENCY


func _bike(path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		check(false, "missing measured curve " + path)
		return
	var data: Dictionary = JSON.parse_string(text)
	var id: String = String(data.get("preset_id", ""))
	if not Presets.PRESETS.has(id):
		check(false, "%s: no preset named %s" % [path.get_file(), id])
		return
	var spec := EngineSpec.new()
	var preset: Dictionary = Presets.PRESETS[id]
	for key in preset:
		spec.set(key, preset[key])
	var sim := EngineSim.new()
	sim.audio_enabled = false
	sim.physics_dt = 1.0 / 2400.0

	print("")
	print("== %s  (%s)" % [id, String(data.get("title", "")).left(70)])
	print("   %6s %8s %8s %7s" % ["rpm", "measured", "sim", "error"])
	var points := _points(data.get("power_samples", []), spec.redline_rpm)
	var sum_abs := 0.0
	var worst := 0.0
	var worst_at := 0.0
	var worst_meas := 0.0
	var worst_sim := 0.0
	for p in points:
		var rpm := float(p[0])
		var measured := float(p[1])
		var torque := _hold(sim, spec, rpm)
		var got := _rear_hp(Units.power_kw(torque, rpm))
		var err := (got - measured) / measured
		sum_abs += absf(err)
		if absf(err) > absf(worst):
			worst = err
			worst_at = rpm
			worst_meas = measured
			worst_sim = got
		print("   %6.0f %8.2f %8.2f %+6.1f%%" % [rpm, measured, got, err * 100.0])
	var mean := sum_abs / maxf(float(points.size()), 1.0)
	print("   mean |error| %.1f%%, worst %+.1f%% at %.0f rpm (%.2f vs %.2f hp)" % [
		mean * 100.0, worst * 100.0, worst_at, worst_sim, worst_meas])
	check(points.size() >= 3, "%s: at least three usable measured points (%d)" % [id, points.size()])
	check(mean <= MEAN_TOL, "%s: mean |error| %.1f%% within %.0f%%" % [id, mean * 100.0, MEAN_TOL * 100.0])
	check(absf(worst) <= WORST_TOL, "%s: worst point %+.1f%% within %.0f%%" % [id, worst * 100.0, WORST_TOL * 100.0])


func _init() -> void:
	await process_frame
	for path in FILES:
		_bike(path)
	print("")
	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
