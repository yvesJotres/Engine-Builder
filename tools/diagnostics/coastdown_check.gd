extends SceneTree

# Coast-down test for every preset: crank, rev to about 70% of redline at full throttle, then close the throttle in
# neutral and record the rpm after 0, 2, 5 and 10 seconds. A real engine falls quickly with the throttle shut. Run:
# godot --headless -s tools/diagnostics/coastdown_check.gd

const DT := 1.0 / 60.0


func _init() -> void:
	await process_frame # autoloads are registered after _init
	for preset_name in Presets.PRESETS.keys():
		var p: Dictionary = Presets.PRESETS[preset_name]
		var spec := EngineSpec.new()
		for key in p.keys():
			spec.set(key, p[key])
		var sim := EngineSim.new()
		for i in 900:
			sim.step(DT, spec, 0.0, true, true, false, false, 1.0)
			if sim.running and sim.rpm > 1000.0:
				break
		var target := spec.redline_rpm * 0.7
		for i in 3600:
			sim.step(DT, spec, 1.0, true, false, false, false, 1.0)
			if sim.rpm >= target:
				break
		var start := sim.rpm
		var readings := []
		var elapsed := 0.0
		for mark in [0.0, 2.0, 5.0, 10.0]:
			while elapsed < mark:
				sim.step(DT, spec, 0.0, true, false, false, false, 1.0)
				elapsed += DT
			readings.append(sim.rpm)
		print("%-28s start %5.0f rpm -> 0 s %5.0f, 2 s %5.0f, 5 s %5.0f, 10 s %5.0f" % [
			preset_name, start, readings[0], readings[1], readings[2], readings[3]])
	quit()
