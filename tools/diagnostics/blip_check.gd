extends SceneTree

# Diagnostic: how fast a throttle blip raises the engine speed with the clutch lever at a given pull, against the speed the
# lower gear needs. Cruise at 60 km/h in 4th, pull the clutch, drop to 3rd, blip the throttle 0 to 1 to 0 over 0.15 s, log rpm.
# Print only: godot --headless -s tools/diagnostics/blip_check.gd

func run(pull: float) -> void:
	var spec := EngineSpec.new()
	var sim := EngineSim.new()
	for i in 720: # crank and start
		sim.step(1.0 / 60.0, spec, 0.0, true, true, false, false, 1.0)
	for i in 600:
		sim.step(1.0 / 60.0, spec, 0.2, true, false, false, false, 1.0)
	sim.gear.gear = 4
	sim.speed = 60.0 / 3.6
	for i in 180:
		sim.step(1.0 / 60.0, spec, 0.2, true, false, false, false, 1.0)
	print("lever pull %.2f (grip %.2f)" % [pull, EngineSim.clutch_grip(pull)])
	print("  cruise: rpm %.0f, speed %.1f m/s, gear %d" % [sim.rpm, sim.speed, sim.gear.gear])
	sim.clutch_pull = pull
	for i in 30:
		sim.step(1.0 / 60.0, spec, 0.0, true, false, false, false, 1.0)
	sim.gear.gear = 3
	var ratio := spec.primary_ratio * sim.gear.ratio() * spec.final_drive
	var target_rpm := sim.speed * ratio / EngineSim.tire_radius_m() * 60.0 / TAU
	print("  pulled to %.2f, now 3rd: rpm %.0f, 3rd needs %.0f" % [pull, sim.rpm, target_rpm])
	var t := 0.0
	var peak := 0.0
	for i in 60:
		var thr := 1.0 if t < 0.15 else 0.0
		sim.step(1.0 / 60.0, spec, thr, true, false, false, false, 1.0)
		t += 1.0 / 60.0
		peak = maxf(peak, sim.rpm)
	print("  blip peak rpm %.0f, after 1 s %.0f, 3rd needs %.0f" % [peak, sim.rpm, target_rpm])

func _init() -> void:
	await process_frame
	run(1.0)
	run(0.7)
	quit(0)
