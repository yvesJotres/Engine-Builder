extends SceneTree

# Diagnostic: cranks the same engine two ways, the game's frame function (fixed 60 fps) and the simulator directly as
# test_engine.gd does, and prints what differs. Run: godot --headless -s tools/diagnostics/crank_compare.gd

const DT := 1.0 / 60.0


func _init() -> void:
	await process_frame
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main._ignition = true
	main._starter_held = true
	print("game: gear %d, ignition %s, displacement %.1f, flywheel %.2f kg, radius %.1f mm, inertia %.5f, lambda %.2f" % [
		main._sim.gear.gear, main._ignition, main.spec.displacement_cc, main.spec.flywheel_kg, main.spec.flywheel_radius_mm,
		main.spec.rotating_inertia(), main._panel.lambda()])
	for i in 600:
		main._process(DT)
	print("game after 10 s of starter: rpm %.0f, running %s, torque %.2f" % [main._sim.rpm, main._sim.running, main._sim.torque])

	var spec := EngineSpec.new()
	var sim := EngineSim.new()
	print("direct: displacement %.1f, flywheel %.2f kg, radius %.1f mm, inertia %.5f" % [
		spec.displacement_cc, spec.flywheel_kg, spec.flywheel_radius_mm, spec.rotating_inertia()])
	for i in 600:
		sim.step(DT, spec, 0.0, true, true, false, false, 1.0)
	print("direct after 10 s of starter: rpm %.0f, running %s, torque %.2f" % [sim.rpm, sim.running, sim.torque])
	quit()
