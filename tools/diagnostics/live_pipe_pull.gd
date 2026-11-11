extends SceneTree

# Wide-open pull at the live 60 Hz cadence with and without the pipe solver, the exhaust layout built the way the app builds it.
# Run: godot --headless --path . -s tools/diagnostics/live_pipe_pull.gd -- <preset> [gap]
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
	var layout := ExhaustLayout.build(spec)
	print("== %s (%d cyl, %s) gap %.2f" % [preset_name, spec.cylinders, spec.stroke_type, gap])
	for pipe in [false, true]:
		var sim := EngineSim.new()
		sim.audio_enabled = false
		sim._build_cylinders(spec)
		sim.exhaust_solver = pipe
		sim.set_audio_layout(layout, spec.cylinders)
		var t := 0.0
		while t < 3.0:
			sim.step(DT, spec, 0.0, true, t < 1.0, false, false, 1.0)
			t += DT
		var total_ms := 0.0
		var worst := 0.0
		var frames := 0
		var rpm_sum := 0.0
		for s in 6:
			var bp := 0.0
			var tq := 0.0
			for f in 60:
				var f0 := Time.get_ticks_usec()
				sim.step(DT, spec, 1.0, true, false, false, false, 1.0)
				var ms := float(Time.get_ticks_usec() - f0) / 1000.0
				total_ms += ms
				worst = maxf(worst, ms)
				frames += 1
				rpm_sum += sim.rpm
				tq += sim.torque
				if sim.exhaust != null:
					bp += sim.exhaust.port_pressure(0) - Cylinder.P0
			print("  pipe=%s s%d rpm %5.0f torque %+7.2f port %+8.1f kPa backfires %d" % [str(pipe), s, sim.rpm, tq / 60.0, bp / 60.0 / 1000.0, sim.backfire_count])
		print(" pipe=%-5s mean rpm %.0f mean %.2f ms/frame worst %.2f ms" % [str(pipe), rpm_sum / frames, total_ms / frames, worst])
	quit(0)
