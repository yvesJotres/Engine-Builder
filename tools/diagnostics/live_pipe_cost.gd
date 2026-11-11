extends SceneTree

# Wall-clock cost of the 1D pipe solver in the live sim loop (60 Hz frame steps), not the offline render path.
# Run: godot --headless --path . -s tools/diagnostics/live_pipe_cost.gd -- <preset> <gap>

const DT := 1.0 / 60.0


func _init() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var preset_name := args[0] if args.size() > 0 else "honda_cbr250rr"
	var gap := float(args[1]) if args.size() > 1 else 0.03
	var p: Dictionary = Presets.PRESETS.get(preset_name, {})
	if p.is_empty():
		print("unknown preset ", preset_name)
		quit(1)
		return
	var spec := EngineSpec.new()
	for key in p.keys():
		spec.set(key, p[key])
	print("preset %s cylinders %d two-stroke %s" % [preset_name, spec.cylinders, spec.stroke_type])
	for pipe in [false, true]:
		var sim := EngineSim.new()
		sim.audio_enabled = false
		sim.exhaust_solver = pipe
		var t := 0.0
		while t < 4.0:
			sim.step(DT, spec, 0.0, true, t < 2.0, false, false, 1.0)
			t += DT
		print("  pipe=%s after start: rpm %.0f running %s exhaust %s" % [str(pipe), sim.rpm, str(sim.running), "null" if sim.exhaust == null else "built"])
		var worst := 0.0
		var frames := 0
		var slow := 0
		var t0 := Time.get_ticks_usec()
		var max_rpm := 0.0
		while t < 16.0:
			var f0 := Time.get_ticks_usec()
			sim.step(DT, spec, gap, true, false, false, false, 1.0)
			if sim.exhaust != null:
				sim.exhaust.take_flow()
			sim.take_intake_flow()
			sim.take_blowdown()
			var ms := float(Time.get_ticks_usec() - f0) / 1000.0
			worst = maxf(worst, ms)
			if ms > 16.67:
				slow += 1
			frames += 1
			max_rpm = maxf(max_rpm, sim.rpm)
			t += DT
		var total_ms := float(Time.get_ticks_usec() - t0) / 1000.0
		print("  pipe=%-5s %d frames | mean %.2f ms, worst %.2f ms, frames over 16.7 ms: %d | max rpm %.0f | backpressure %+.0f Pa" % [str(pipe), frames, total_ms / frames, worst, slow, max_rpm, sim.backpressure_pa() - Cylinder.P0])
	quit(0)
