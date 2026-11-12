extends SceneTree

# The limiter must not bang. A fuel cut decided per FRAME can cut the spark of a charge that was already fuelled at
# intake closing, and that charge leaves unlit into a hot port and pops - measured 311 pops in 40 s on the CBR1000RR-R
# before this test existed. The quickshifter cut is the opposite case: it cuts the spark only, on purpose, after the
# fuelling, and must keep popping.
# Run: godot --headless --path . --quit-after 6000 -s res://tests/unit/engine/limiter_backfire_test.gd   (prints PASS or FAIL)

const DT := 1.0 / 60.0

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func _spec() -> EngineSpec:
	var spec := EngineSpec.new()
	for key in Presets.PRESETS["honda_cbr1000rrr_sp"].keys():
		spec.set(key, Presets.PRESETS["honda_cbr1000rrr_sp"][key])
	spec.quickshifter = true
	return spec


func _start(spec: EngineSpec) -> EngineSim:
	var sim := EngineSim.new()
	sim.audio_enabled = false
	for i in 240:
		sim.step(DT, spec, 0.0, true, i < 60, false, false, 1.0)
	sim.gear.gear = 0
	sim.clutch_pull = 1.0
	return sim


func _init() -> void:
	var spec := _spec()

	# 40 s held wide open on the stop
	var lim := _start(spec)
	var cut_frames := 0
	for i in 2400:
		lim.step(DT, spec, 1.0, true, false, false, false, 1.0)
		if lim.intake.limiter_cut:
			cut_frames += 1
	print("limiter: %.0f rpm, %d of 2400 frames cut, %d pops" % [lim.rpm, cut_frames, lim.backfire_count])
	check(cut_frames > 0, "the limiter actually cut during the run (%d frames)" % cut_frames)
	check(lim.backfire_count == 0, "holding on the limiter does not pop, got %d" % lim.backfire_count)

	# quickshift: spark cut after fuelling, which must still pop. Two preconditions: the pipe has to be hot (the wall holds the
	# heat, Cylinder.PORT_THERMAL_TAU), and the shift has to land below the limiter, whose cut takes the fuel as well.
	var qs := _start(spec)
	var redline := spec.redline_rpm
	spec.redline_rpm = 22000.0
	for i in 1200:
		qs.step(DT, spec, 1.0, true, false, false, false, 1.0)
	spec.redline_rpm = redline
	for i in 60:
		qs.step(DT, spec, 0.45, true, false, false, false, 1.0)
	var before := qs.backfire_count
	for i in 10:
		qs.gear.gear = 1
		qs.ecu.trigger_quickshifter(spec)
		for j in 40:
			qs.step(DT, spec, 0.45, true, false, false, false, 1.0)
	print("quickshift: %d pops over 10 cuts at %.0f rpm" % [qs.backfire_count - before, qs.rpm])
	check(qs.backfire_count - before > 0, "a quickshift cut still pops")

	print("limiter_backfire_test: %s" % ("PASS" if _fails == 0 else "FAIL"))
	quit(0 if _fails == 0 else 1)
