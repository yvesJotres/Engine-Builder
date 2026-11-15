extends SceneTree

# A quickshifter upshift cuts the spark after the cylinders already have fuel in them. That fuel leaves unlit into the hot
# exhaust and pops, as a real bike does on an upshift. Steady idle, with no cut, must not pop.
#
# The pipe has to be HOT for that: the port/header wall holds the heat (Cylinder.PORT_THERMAL_TAU) and an unlit charge only
# catches on hot metal, so a cold-revved engine does not bang on its first shift. _start therefore holds the engine wide open
# with the limiter out of the way until the wall is up to temperature - which is what a real bike needs too.
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
	# heat the pipe on fired cycles: hold it wide open with the limiter out of the way, then put the limiter back
	var redline := spec.redline_rpm
	spec.redline_rpm = 22000.0
	for i in 1200:
		sim.step(DT, spec, 1.0, true, false, false, false, 1.0)
	spec.redline_rpm = redline
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

	# high rpm, then a quickshifter upshift: the cut pops. Roll off first so the shift lands below the limiter: a limiter cut
	# takes the fuel as well, so its cycles have nothing to leave unlit.
	var shift := _start(spec)
	for i in 60:
		shift.step(DT, spec, 0.45, true, false, false, false, 1.0)
	print("shift made at %.0f rpm, pipe at %.0f K" % [shift.rpm, shift.cylinders[0]._port_heat])
	var before := shift.backfire_count
	var engaged := shift.ecu.trigger_quickshifter(spec)
	check(engaged, "the quickshifter engages at high rpm")
	for i in 40:
		shift.step(DT, spec, 1.0, true, false, false, false, 1.0)
	check(shift.backfire_count > before, "a quickshifter upshift pops at high rpm, got %d" % (shift.backfire_count - before))

	print("cut_pop_test: %s" % ("PASSED" if _fails == 0 else "FAILED"))
	quit(0 if _fails == 0 else 1)
