extends SceneTree

# Rev probe: warms the CBR150R at idle, then holds the throttle wide open in neutral and prints rpm over time.
# Run: godot --headless --path . -s res://tools/diagnostics/rev_probe.gd

const PHYS_DT := 1.0 / 2400.0


func _init() -> void:
	var spec := EngineSpec.new()
	var preset: Dictionary = Presets.PRESETS["honda_cbr150r"]
	for key in preset.keys():
		spec.set(key, preset[key])
	var sim := EngineSim.new()
	sim.physics_dt = PHYS_DT
	var t := 0.0
	while t < 2.0:
		sim.step(1.0 / 60.0, spec, 0.0, true, true, true, false, 1.0)
		t += 1.0 / 60.0
	var next_log := 0.0
	while t < 12.0:
		sim.step(1.0 / 60.0, spec, 1.0, true, false, true, false, 1.0)
		t += 1.0 / 60.0
		if t >= next_log:
			print("t=%5.2f rpm=%7.0f running=%s" % [t, sim.rpm, str(sim.running)])
			next_log += 0.5
	quit(0)
