extends SceneTree

# Diagnostic: pops and knocks at idle with the intake centre at the 300 degrees the old panel clamped it to, against the stock 470.
func _init() -> void:
	await process_frame
	for centre in [470.0, 300.0]:
		var spec := EngineSpec.new()
		spec.intake_centre_deg = centre
		var sim := EngineSim.new()
		for i in 720:
			sim.step(1.0 / 60.0, spec, 0.0, true, true, false, false, 1.0)
		var b0 := sim.backfire_count
		for i in 600:
			sim.step(1.0 / 60.0, spec, 0.0, true, false, false, false, 1.0)
		print("intake centre %.0f: idle %.0f rpm, backfire pops in 10 s: %d, flow %.2f g/s" % [centre, sim.rpm, sim.backfire_count - b0, sim.fuel_flow])
	quit(0)
