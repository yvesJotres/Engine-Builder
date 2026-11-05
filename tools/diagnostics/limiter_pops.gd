extends SceneTree

# Diagnostic: how many backfires a rev-limiter session makes, and how much energy each one releases. Print only.
func _init() -> void:
	await process_frame
	var spec := EngineSpec.new()
	var sim := EngineSim.new()
	for i in 720:
		sim.step(1.0 / 60.0, spec, 0.0, true, true, false, false, 1.0)
	for i in 600:
		sim.step(1.0 / 60.0, spec, 0.0, true, false, false, false, 1.0)
	var t := 0.0
	var seen := 0
	var first_cut := -1.0
	for i in 3600:
		sim.step(1.0 / 60.0, spec, 1.0, true, false, false, false, 1.0)
		t += 1.0 / 60.0
		if sim.backfire_count != seen:
			print("t %.3f s  rpm %.0f  backfires so far %d  energy %.1f J  limiter %s" % [t, sim.rpm, sim.backfire_count, sim.last_backfire_j, str(sim.limiter_active)])
			seen = sim.backfire_count
		if sim.limiter_active and first_cut < 0.0:
			first_cut = t
		if first_cut > 0.0 and t > first_cut + 1.0:
			break
	print("total %d backfires in %.2f s after the first limiter cut" % [sim.backfire_count, t - first_cut])
	quit(0)
