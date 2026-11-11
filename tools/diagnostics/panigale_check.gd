extends SceneTree

# Ducati Panigale V4: idle at closed throttle, then wide-open revs in neutral, printing rpm each second. Run:
# godot --headless -s tools/diagnostics/panigale_check.gd
func _init() -> void:
	await process_frame
	var p: Dictionary = Presets.PRESETS["ducati_panigale_v4"]
	var spec := EngineSpec.new()
	for key in p.keys():
		spec.set(key, p[key])
	var sim := EngineSim.new()
	var frames := 0
	while not sim.running and frames < 3600:
		sim.step(1.0 / 60.0, spec, 0.0, true, true, false, false, 1.0)
		frames += 1
	print("fired after %d frames, rpm %.0f" % [frames, sim.rpm])
	var line := ""
	for s in 8:
		for i in 60:
			sim.step(1.0 / 60.0, spec, 0.0, true, false, false, false, 1.0)
		line += " %.0f" % sim.rpm
	print("idle, rpm each second:" + line)
	line = ""
	for s in 8:
		for i in 60:
			sim.step(1.0 / 60.0, spec, 1.0, true, false, false, false, 1.0)
		line += " %.0f" % sim.rpm
	print("full throttle, rpm each second:" + line + "  (redline %.0f, limiter 16500)" % spec.redline_rpm)
	quit()
