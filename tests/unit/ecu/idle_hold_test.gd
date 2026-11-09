extends SceneTree

# The idle must settle on the ECU's target and stay there. It used to hunt: the overrun fuel cut pulled the idle loops back to
# neutral, which opened the idle valve and sent the rpm up again, so the engine cycled around 1.4 times its target. For each
# bike, cranked from cold and left at a closed throttle, the last six seconds must sit near the target with little spread.
# Exits 1 on any failure. Run: godot --headless --path . -s res://tests/unit/ecu/idle_hold_test.gd

const PRESETS := ["harley_sportster_883", "honda_cbr250rr", "kawasaki_zx25r"]
const SETTLE_S := 8.0
const MEASURE_S := 6.0
const MAX_OFFSET := 0.08 # mean idle within 8% of the target
const MAX_SPREAD := 0.05 # standard deviation within 5% of the target

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func _init() -> void:
	await process_frame
	for name in PRESETS:
		_idle(name)
	print("idle_hold_test: %s" % ("PASSED" if _fails == 0 else "FAILED"))
	quit(0 if _fails == 0 else 1)


func _idle(name: String) -> void:
	var spec := EngineSpec.new()
	var p: Dictionary = Presets.PRESETS[name]
	for key in p.keys():
		spec.set(key, p[key])
	var sim := EngineSim.new()
	sim.physics_dt = 1.0 / 2400.0
	sim.fuel.set_kind(spec.fuel)
	var target := spec.idle_target_rpm
	# crank until it runs, as a player would
	var guard := 0
	while (not sim.running or sim.rpm < target * 0.9) and guard < 40 * 2400:
		sim.step(sim.physics_dt, spec, 0.0, true, true, false, false, 1.0)
		guard += 1
	var samples: Array[float] = []
	for frame in int((SETTLE_S + MEASURE_S) * 60.0):
		for i in 2400 / 60:
			sim.step(sim.physics_dt, spec, 0.0, true, false, false, false, 1.0)
		if frame >= int(SETTLE_S * 60.0):
			samples.append(sim.rpm)
	var mean := 0.0
	for v in samples:
		mean += v
	mean /= samples.size()
	var variance := 0.0
	for v in samples:
		variance += (v - mean) * (v - mean)
	var spread := sqrt(variance / samples.size())
	check(absf(mean - target) <= target * MAX_OFFSET, "%s: idle mean %.0f is not within %.0f%% of the target %.0f" % [name, mean, MAX_OFFSET * 100.0, target])
	check(spread <= target * MAX_SPREAD, "%s: idle spread %.0f rpm is more than %.0f%% of the target %.0f" % [name, spread, MAX_SPREAD * 100.0, target])
