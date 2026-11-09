extends SceneTree

# Headless check: the clutch must stay finite and bounded in every gear, with a light and a heavy flywheel and long
# frames, which made the old explicit clutch blow up. Run: godot --headless -s tests/unit/drivetrain/clutch_stability_test.gd
# Exit code 1 on any failure.

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: " + msg)


func _init() -> void:
	var inertia := 0.03
	var mass := 220.0
	var ratio := 9.0
	var radius := 0.3
	var dt := 1.0 / 1200.0
	for speeds in [[300.0, 5.0], [100.0, 10.0]]:
		var crank: float = speeds[0]
		var wheel: float = speeds[1]
		var transfer := EngineSim.clutch_transfer_torque(crank, wheel, inertia, mass, ratio, radius, 100000.0, dt)
		var efficiency := EngineSim.DRIVE_EFFICIENCY if transfer >= 0.0 else 1.0 / EngineSim.DRIVE_EFFICIENCY
		var final_crank := crank - transfer * dt / inertia
		var final_wheel := wheel + transfer * ratio / radius * efficiency * dt / mass
		var initial_energy := 0.5 * inertia * crank * crank + 0.5 * mass * wheel * wheel
		var final_energy := 0.5 * inertia * final_crank * final_crank + 0.5 * mass * final_wheel * final_wheel
		check(absf(final_crank - final_wheel * ratio / radius) < 0.001, "clutch locks without overshooting in either power direction")
		check(final_energy <= initial_energy + 0.001, "clutch coupling does not create kinetic energy")
		var limited := EngineSim.clutch_transfer_torque(crank, wheel, inertia, mass, ratio, radius, 3.0, dt)
		check(absf(limited) <= 3.0, "slipping clutch respects torque capacity")
		var slipping_crank := crank - limited * dt / inertia
		var slipping_wheel := wheel + limited * ratio / radius * efficiency * dt / mass
		var slipping_energy := 0.5 * inertia * slipping_crank * slipping_crank + 0.5 * mass * slipping_wheel * slipping_wheel
		check(slipping_energy <= initial_energy + 0.001, "slipping clutch does not create kinetic energy")
		check((crank - wheel * ratio / radius) * (slipping_crank - slipping_wheel * ratio / radius) >= 0.0, "slipping clutch does not reverse relative motion")
	check(EngineSim.clutch_transfer_torque(300.0, 5.0, inertia, mass, ratio, radius, 0.0, dt) == 0.0, "open clutch transfers no torque")
	for flywheel in [2.5, 0.5]:
		for gear_index in 6:
			var spec := EngineSpec.new()
			spec.flywheel_kg = flywheel
			var sim := EngineSim.new()
			# a bike already rolling at 12 m/s with the engine at about 3,800 rpm, then the clutch is engaged in each gear
			sim.running = true
			sim.rpm = 3800.0
			sim.omega = sim.rpm * TAU / 60.0
			sim.speed = 12.0
			sim.gear.gear = gear_index + 1 # set directly: shift_up from neutral skips 1st
			# 150 frames of 100 ms at half throttle, the worst case a hitch can produce; the sim caps each step itself
			for i in 150:
				sim.step(0.1, spec, 0.5, true, false, false, false, 1.0)
			var label := "flywheel %.1f kg, gear %d" % [flywheel, gear_index + 1]
			check(is_finite(sim.omega) and is_finite(sim.speed) and is_finite(sim.rpm), label + ": state is not finite")
			check(sim.rpm < spec.redline_rpm * 1.5, label + ": rpm %.0f runs away" % sim.rpm)
			check(sim.speed >= 0.0, label + ": speed is negative")
			print("%s: rpm %.0f, speed %.2f m/s" % [label, sim.rpm, sim.speed])
	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
