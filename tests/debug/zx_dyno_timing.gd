extends SceneTree

# Runs the automatic dyno sweep on the ZX-25R one 60 Hz frame at a time, as the game does, and reports wall time per frame.
# Print only. Run: godot --headless --path . -s tests/debug/zx_dyno_timing.gd
const MAX_FRAMES := 60 * 240


func _init() -> void:
	var spec := EngineSpec.new()
	var p: Dictionary = Presets.PRESETS["kawasaki_zx25r"]
	for key in p.keys():
		spec.set(key, p[key])
	var sim := EngineSim.new()
	sim.physics_dt = 1.0 / 2400.0
	sim.fuel.set_kind(spec.fuel)
	var dyno = DynoTest.new()
	dyno.start(spec, sim)
	var worst := 0.0
	var total := 0.0
	var frames := 0
	while dyno.active() and frames < MAX_FRAMES:
		var t0 := Time.get_ticks_usec()
		dyno.advance(1.0 / 60.0, sim, spec, 1.0, true)
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		worst = maxf(worst, ms)
		total += ms
		frames += 1
		if frames % 600 == 0:
			print("frame %d  %s  rpm %.0f  wall so far %.1f s  worst frame %.1f ms" % [frames, dyno.status_text(), sim.rpm, total / 1000.0, worst])
	print("FINISHED after %d frames (%.1f s of game time), %.1f s of wall time, worst frame %.1f ms, active %s, status: %s" % [frames, frames / 60.0, total / 1000.0, worst, str(dyno.active()), dyno.status])
	quit()
