extends SceneTree

# Start probe: cranks the CBR150R from rest in neutral with the starter held for a set time, then releases it.
# Prints rpm and running state so a start that stalls shows where it fails.
# Run: godot --headless --path . -s res://tools/diagnostics/start_probe.gd -- <hold_seconds>

const PHYS_DT := 1.0 / 1200.0


func _init() -> void:
	var hold := 3.0
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		hold = float(args[0])
	var spec := EngineSpec.new()
	var preset: Dictionary = Presets.PRESETS["honda_cbr150r"]
	for key in preset.keys():
		spec.set(key, preset[key])
	var sim := EngineSim.new()
	sim.physics_dt = PHYS_DT
	var t := 0.0
	var next_log := 0.0
	var caught_at := -1.0
	var max_rpm := 0.0
	while t < 12.0:
		var starter := t < hold
		sim.step(1.0 / 60.0, spec, 0.0, true, starter, true, false, 1.0)
		t += 1.0 / 60.0
		max_rpm = maxf(max_rpm, sim.rpm)
		if caught_at < 0.0 and sim.running:
			caught_at = t
		if t >= next_log:
			print("t=%5.2f starter=%s rpm=%7.1f running=%s omega=%.2f" % [t, str(starter), sim.rpm, str(sim.running), sim.omega])
			next_log += 0.5
	print("hold=%.1fs caught_at=%.2fs max_rpm=%.0f final_rpm=%.0f final_running=%s" % [hold, caught_at, max_rpm, sim.rpm, str(sim.running)])
	quit(0)
