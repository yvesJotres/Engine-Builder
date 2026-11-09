extends SceneTree

# Audio recording is optional. The pipe solver stays off, so torque does not depend on it.
# Run: godot --headless -s tests/visual/render/audio_gate_test.gd

var _fails := 0


func check(ok: bool, msg: String) -> void:
	print(("ok   " if ok else "FAIL ") + msg)
	if not ok:
		_fails += 1


func _run(enabled: bool) -> Dictionary:
	var spec := EngineSpec.new()
	var sim := EngineSim.new()
	sim.audio_enabled = enabled
	sim.physics_dt = 1.0 / 2400.0
	var rpm := 4000.0
	for _i in 4:
		sim.omega = rpm * TAU / 60.0
		sim.rpm = rpm
		sim.running = true
		sim.step(0.05, spec, 0.8, true, false, true, false, 1.0)
	var blow := sim.take_blowdown()
	var intake := sim.take_intake_flow()
	return {"torque": sim.torque, "back": sim.backpressure_pa(), "blow": blow.size(), "intake": intake.size()}


func _init() -> void:
	var on := _run(true)
	var off := _run(false)
	check(on.blow > 100 and on.intake > 100, "audio on records valve flow (%d, %d)" % [on.blow, on.intake])
	check(off.blow == 0 and off.intake == 0, "audio off records nothing")
	check(absf(float(on.torque) - float(off.torque)) < 0.01, "shaft torque matches with audio off (%.3f vs %.3f N·m)" % [on.torque, off.torque])
	check(absf(float(on.back) - float(off.back)) < 1.0, "backpressure matches with audio off (%.0f Pa)" % float(off.back))
	var sound := EngineSound.new()
	sound.audio_enabled = false
	var silent := sound.render(256)
	var energy := 0.0
	for frame in silent:
		energy += frame.x * frame.x
	check(silent.size() == 256 and energy == 0.0, "a muted player skips the convolution")
	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
