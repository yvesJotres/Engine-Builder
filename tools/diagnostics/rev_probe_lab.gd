extends SceneTree

# Same setup as the audio lab's rev render (1/3600 s step, idle warm-up, wide open in neutral): prints the rpm the sound layers see.
func _init() -> void:
	var spec := EngineSpec.new()
	var preset: Dictionary = Presets.PRESETS["honda_cbr150r"]
	for key in preset.keys():
		spec.set(key, preset[key])
	var sim := EngineSim.new()
	sim.physics_dt = 1.0 / 3600.0
	var steps := 0
	while (not sim.running or sim.rpm < spec.idle_target_rpm * 1.5) and steps < int(40.0 / sim.physics_dt):
		sim.step(sim.physics_dt, spec, 0.0, true, true, false, false, 1.0)
		steps += 1
	for i in int(1.0 / sim.physics_dt):
		sim.step(sim.physics_dt, spec, 0.0, true, false, false, false, 1.0)
	print("after warm-up rpm=%.0f idle_target=%.0f" % [sim.rpm, spec.idle_target_rpm])
	var clock := 0.0
	var next_log := 0.0
	while clock < 10.0:
		sim.step(sim.physics_dt, spec, 1.0, true, false, false, false, 1.0)
		clock += sim.physics_dt
		if clock >= next_log:
			print("t=%5.2f rpm=%7.0f" % [clock, sim.rpm])
			next_log += 0.5
	quit(0)
