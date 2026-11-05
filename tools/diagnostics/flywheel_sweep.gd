extends SceneTree

# Diagnostic: how idle, the wide-open pull in neutral and wide-open torque depend on the flywheel. Run:
# godot --headless -s tools/diagnostics/flywheel_sweep.gd

const DT := 1.0 / 60.0


func _init() -> void:
	for kg in [2.5, 4.0, 6.0]:
		for radius_mm in [57.3, 75.0]:
			var spec := EngineSpec.new()
			spec.flywheel_kg = kg
			spec.flywheel_radius_mm = radius_mm
			var sim := EngineSim.new()
			for i in 600:
				sim.step(DT, spec, 0.0, true, true, true, false, 1.0)
			for i in 1200:
				sim.step(DT, spec, 0.0, true, false, true, false, 1.0)
			var idle := sim.rpm
			var idle_running := sim.running
			for i in 2400:
				sim.step(DT, spec, 1.0, true, false, true, false, 1.0)
			var wot := sim.rpm
			var sim2 := EngineSim.new()
			spec.flywheel_kg = kg
			for i in 600:
				sim2.step(DT, spec, 0.0, true, true, true, false, 1.0)
			for i in 1200:
				sim2.step(DT, spec, 0.0, true, false, true, false, 1.0)
			var torque_sum := 0.0
			var torque_n := 0
			for i in 1200:
				sim2.step(DT, spec, 0.6, true, false, false, false, 1.0)
			print("flywheel %.1f kg, radius %.1f mm, I %.4f: idle %4.0f rpm (running %s), after WOT %5.0f rpm" % [
				kg, radius_mm, spec.rotating_inertia(), idle, idle_running, wot])
	quit()
