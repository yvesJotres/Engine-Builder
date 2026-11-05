extends SceneTree

# Idle check for every preset: crank in neutral, let the engine settle at closed throttle, then report the idle speed and
# how steady it is over the last two seconds. Multi-cylinder and high-redline engines are the focus. Run:
# godot --headless -s tools/diagnostics/idle_presets_check.gd

const DT := 1.0 / 60.0


func _init() -> void:
	await process_frame # autoloads are registered after _init
	for preset_name in Presets.PRESETS.keys():
		var p: Dictionary = Presets.PRESETS[preset_name]
		var spec := EngineSpec.new()
		for key in p.keys():
			spec.set(key, p[key])
		var sim := EngineSim.new()
		var started := false
		for i in 900:
			sim.step(DT, spec, 0.0, true, true, false, false, 1.0)
			if sim.running and sim.rpm > 1000.0:
				started = true
				break
		var lo := 1.0e9
		var hi := 0.0
		for i in 1200:
			sim.step(DT, spec, 0.0, true, false, false, false, 1.0)
			if i >= 600:
				lo = minf(lo, sim.rpm)
				hi = maxf(hi, sim.rpm)
		print("%-28s %d cyl, redline %5.0f: started %s, idle %5.0f rpm (swing %4.0f to %4.0f) running %s" % [
			preset_name, spec.cylinders, spec.redline_rpm, started, sim.rpm, lo, hi, sim.running])
	quit()
