extends SceneTree

# Headless check: the clutch must stay finite and bounded in every gear, with a light and a heavy flywheel and long
# frames, which made the old explicit clutch blow up. Run: godot --headless -s tests/clutch_stability_test.gd
# Exit code 1 on any failure.

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: " + msg)


func _init() -> void:
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
