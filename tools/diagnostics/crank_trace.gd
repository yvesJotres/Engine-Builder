extends SceneTree

# Diagnostic: crank speed over time with the starter held, for two flywheel masses. Run:
# godot --headless -s tools/diagnostics/crank_trace.gd

const DT := 1.0 / 60.0


func _init() -> void:
	for kg in [2.5, 4.0]:
		var spec := EngineSpec.new()
		spec.flywheel_kg = kg
		var sim := EngineSim.new()
		var line := "flywheel %.1f kg, I %.4f: rpm every second:" % [kg, spec.rotating_inertia()]
		for i in 600:
			sim.step(DT, spec, 0.0, true, true, true, false, 1.0)
			if i % 60 == 59:
				line += " %.0f" % sim.rpm
		print(line)
	quit()
