extends SceneTree

# A quickshifter upshift cuts the spark after the cylinders already have fuel in them. That fuel leaves unlit into the hot
# exhaust and pops, as a real bike does on an upshift. Steady idle, with no cut, must not pop.
# Exits 1 on any failure. Run: godot --headless --path . -s res://tests/unit/ecu/cut_pop_test.gd

const DT := 1.0 / 60.0

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func _start(spec: EngineSpec) -> EngineSim:
	var sim := EngineSim.new()
	sim.audio_enabled = false
	for i in 180:
		sim.step(DT, spec, 0.0, true, true, false, false, 1.0)
	sim.gear.gear = 0
	sim.clutch_pull = 1.0
	return sim


func _init() -> void:
	var spec := EngineSpec.new()
	var preset: Dictionary = Presets.PRESETS["honda_cbr1000rrr_sp"]
	for key in preset.keys():
		spec.set(key, preset[key])
	spec.quickshifter = true

	# steady idle, no cut: no pops
	var steady := _start(spec)
	for i in 300:
		steady.step(DT, spec, 0.0, true, false, false, false, 1.0)
	check(steady.rpm > 800.0 and steady.rpm < 3000.0, "the steady run idles, got %.0f rpm" % steady.rpm)
	check(steady.backfire_count == 0, "steady idle does not pop, got %d" % steady.backfire_count)

	# high rpm, then a quickshifter upshift: the cut pops
	var shift := _start(spec)
	for i in 900:
		shift.step(DT, spec, 1.0, true, false, false, false, 1.0)
		if shift.rpm > 12000.0:
			break
	var before := shift.backfire_count
	var engaged := shift.ecu.trigger_quickshifter(spec)
	check(engaged, "the quickshifter engages at high rpm")
	for i in 40:
		shift.step(DT, spec, 1.0, true, false, false, false, 1.0)
	check(shift.backfire_count > before, "a quickshifter upshift pops at high rpm, got %d" % (shift.backfire_count - before))

	print("cut_pop_test: %s" % ("PASSED" if _fails == 0 else "FAILED"))
	quit(0 if _fails == 0 else 1)
