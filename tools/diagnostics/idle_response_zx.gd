extends SceneTree

# Diagnostic: idle speed, pops and knocks at idle, and how fast the throttle responds, for the default engine. Print only.
func _init() -> void:
	await process_frame
	var spec := EngineSpec.new()
	var p: Dictionary = Presets.PRESETS["kawasaki_zx25r"]
	for key in p.keys():
		spec.set(key, p[key])
	var sim := EngineSim.new()
	for i in 720:
		sim.step(1.0 / 60.0, spec, 0.0, true, true, false, false, 1.0)
	for sec in 6:
		for i in 60:
			sim.step(1.0 / 60.0, spec, 0.0, true, false, false, false, 1.0)
		print("idle t+%d s: rpm %5.0f  trim %+.1f  air %.3f  backfires %d  knocks %d  limiter %s" % [sec + 1, sim.rpm, sim.ecu.trim, sim.ecu.air_factor(), sim.backfire_count, sim.knock_count, str(sim.limiter_active)])
	# throttle: open to half, read rpm each 0.1 s for 2 s, then close
	var t := 0.0
	var first_rise := -1.0
	for i in 120:
		sim.step(1.0 / 60.0, spec, 0.5, true, false, false, false, 1.0)
		t += 1.0 / 60.0
		if first_rise < 0.0 and sim.rpm > 2000.0:
			first_rise = t
		if i % 12 == 11:
			print("open 50%%  t %.1f s: rpm %5.0f  trim %+.1f  air %.3f" % [t, sim.rpm, sim.ecu.trim, sim.ecu.air_factor()])
	print("time to 2000 rpm after opening: %.2f s" % first_rise)
	t = 0.0
	for i in 120:
		sim.step(1.0 / 60.0, spec, 0.0, true, false, false, false, 1.0)
		t += 1.0 / 60.0
		if i % 24 == 23:
			print("closed     t %.1f s: rpm %5.0f  trim %+.1f  air %.3f" % [t, sim.rpm, sim.ecu.trim, sim.ecu.air_factor()])
	quit(0)
