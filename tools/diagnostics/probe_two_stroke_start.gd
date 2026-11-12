extends SceneTree

# Can a two-stroke actually start? Cranks with the starter, then lets it idle, printing rpm, combustion state and the
# charge the cylinder got each second.
# Run: godot --headless --path . -s res://tools/diagnostics/probe_two_stroke_start.gd [preset]

const DT := 1.0 / 60.0


func _init() -> void:
	var argv := OS.get_cmdline_user_args()
	for id in (argv if argv.size() > 0 else ["yamaha_rd350", "honda_trx520"]):
		if not Presets.PRESETS.has(id):
			print("%s: no such preset" % id)
			continue
		var spec := EngineSpec.new()
		var preset: Dictionary = Presets.PRESETS[id]
		for key in preset:
			spec.set(key, preset[key])
		var sim := EngineSim.new()
		sim.audio_enabled = false
		print("")
		print("== %s  %d cyl  %.0f cc  stroke_type %s  compression %.1f  redline %.0f" % [
			id, spec.cylinders, spec.displacement_cc, spec.stroke_type, spec.compression_ratio, spec.redline_rpm])
		print("   %5s %8s %9s %9s %9s %8s %7s %7s" % ["t", "rpm", "running", "burn_J", "fresh_kg", "lambda", "limit", "thr"])
		for frame in 600:
			# 5 s of cranking, then release: the engine has to catch on its own
			var starter := frame < 300
			var throttle := 0.15 if starter else 0.0
			sim.step(DT, spec, throttle, true, starter, false, false, 1.0)
			if frame % 60 == 59:
				var c = sim.cylinders[0]
				print("   %5.1f %8.0f %9s %9.2f %9.6f %8.3f %7s %7.2f" % [
					(frame + 1) * DT, sim.rpm, str(sim.running), c.burn_energy, c.last_fresh_kg, c.last_lambda,
					str(sim.limiter_active), throttle])
		print("   final: running %s, rpm %.0f" % [str(sim.running), sim.rpm])
	quit(0)
