extends SceneTree

# Checks the clutch friction zone: the lever's grip curve, the plates settling at the grip for a held lever, a Shift pull-in
# opening the clutch fully, and the slow return after Shift is let go. Run: godot --headless -s tests/clutch_bite_test.gd
# (exit code 1 on failure)

var _fails := 0


func check(ok: bool, msg: String) -> void:
	print(("ok   " if ok else "FAIL ") + msg)
	if not ok:
		_fails += 1


func _init() -> void:
	await process_frame
	check(absf(EngineSim.clutch_grip(0.0) - 1.0) < 1e-6, "fully engaged at rest")
	check(absf(EngineSim.clutch_grip(EngineSim.CLUTCH_BITE_START) - 1.0) < 1e-6, "still fully engaged at the bite point")
	check(absf(EngineSim.clutch_grip(EngineSim.CLUTCH_BITE_END)) < 1e-6, "fully open at the end of the friction zone")
	check(absf(EngineSim.clutch_grip(1.0)) < 1e-6, "fully open with the lever all the way out")
	var prev := 2.0
	var monotone := true
	for i in 101:
		var g := EngineSim.clutch_grip(i / 100.0)
		if g > prev + 1e-9:
			monotone = false
		prev = g
	check(monotone, "grip falls as the lever is pulled, with no jumps back")

	var spec := EngineSpec.new()
	var sim := EngineSim.new()
	for i in 720:
		sim.step(1.0 / 60.0, spec, 0.0, true, true, false, false, 1.0)
	# a lever held in the friction zone: the plates settle at the grip for that pull
	sim.clutch_pull = 0.7
	for i in 120:
		sim.step(1.0 / 60.0, spec, 0.0, true, false, false, false, 1.0)
	check(absf(sim.clutch_engage - EngineSim.clutch_grip(0.7)) < 0.01, "held at pull 0.7, the plates settle at grip %.2f (%.2f)" % [EngineSim.clutch_grip(0.7), sim.clutch_engage])
	# the Shift key pulls the clutch fully apart
	sim.clutch_pull = 0.0
	for i in 30:
		sim.step(1.0 / 60.0, spec, 0.0, true, false, true, false, 1.0)
	check(sim.clutch_engage < 0.01, "Shift pulls the clutch fully apart (%.2f)" % sim.clutch_engage)
	# Shift let go: the plates come back slowly, not in a snap
	for i in 18:
		sim.step(1.0 / 60.0, spec, 0.0, true, false, false, false, 1.0)
	check(sim.clutch_engage < 0.5, "after Shift is let go, the plates come back slowly (%.2f after 0.3 s)" % sim.clutch_engage)
	for i in 120:
		sim.step(1.0 / 60.0, spec, 0.0, true, false, false, false, 1.0)
	check(sim.clutch_engage > 0.99, "and fully engaged again after about 1.5 s (%.2f)" % sim.clutch_engage)
	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
