extends SceneTree

# Diagnostic: the CBR150R at full throttle in 6th gear at 91 km/h, the speed in the screenshot: gas torque, friction, road load,
# and the speed it settles at. Print only.
func _init() -> void:
	await process_frame
	var spec := EngineSpec.new()
	var sim := EngineSim.new()
	for i in 720:
		sim.step(1.0 / 60.0, spec, 0.0, true, true, false, false, 1.0)
	for i in 600:
		sim.step(1.0 / 60.0, spec, 0.0, true, false, false, false, 1.0)
	sim.gear.gear = 6
	sim.speed = 91.0 / 3.6
	for k in 3600:
		sim.step(1.0 / 60.0, spec, 1.0, true, false, false, false, 1.0)
		if k % 600 == 599:
			print("t %2d s: speed %5.1f km/h  rpm %6.0f" % [(k + 1) / 60, sim.speed * 3.6, sim.rpm])
	print("top gear ratio %.4f, final drive %.2f, primary %.2f, wheel radius %.3f m" % [sim.gear.ratio(), spec.final_drive, spec.primary_ratio, EngineSim.tire_radius_m()])
	quit(0)
