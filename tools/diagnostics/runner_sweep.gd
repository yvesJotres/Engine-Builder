extends SceneTree

# Runs the dyno on one preset at several intake runner lengths and prints the torque shape, without changing any file.
# Run: godot --headless --path . -s tools/diagnostics/runner_sweep.gd -- honda_cbr250rr_sp_qs 0.125 0.09 0.07


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var preset_id := args[0] if args.size() > 0 else "honda_cbr250rr_sp_qs"
	var lengths: Array = []
	for i in range(1, args.size()):
		lengths.append(float(args[i]))
	if lengths.is_empty():
		lengths = [0.125]
	print("runner_m  crankNm@4k 6k 8k 10k 11k 13k   peak_crank_hp@rpm   VE@4k VE@10k")
	for length in lengths:
		var spec := DynoRunner.spec_for(preset_id)
		spec.runner_length_m = length
		var sim := EngineSim.new()
		sim.fuel.set_kind(spec.fuel)
		var dyno := DynoTest.new()
		dyno.reference_id = preset_id
		dyno.start(spec, sim)
		var frames := 0
		while dyno.active() and frames < 200000:
			dyno.advance(1.0 / 60.0, sim, spec, 1.0, true)
			frames += 1
		var r := dyno.result()
		var at := func(rpm: float) -> float:
			var best := 0.0
			var gap := 1e9
			for p in r.curve:
				if absf(p.rpm - rpm) < gap:
					gap = absf(p.rpm - rpm)
					best = p.torque
			return best
		var peak: Dictionary = r.peak_hp
		print("%.3f     %5.1f %5.1f %5.1f %5.1f %5.1f %5.1f      %6.2f@%5.0f      -" % [
			length, at.call(4000.0), at.call(6000.0), at.call(8000.0), at.call(10000.0), at.call(11000.0), at.call(13000.0),
			peak.hp, peak.rpm])
	quit(0)
