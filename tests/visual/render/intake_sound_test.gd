extends SceneTree

# The intake sound is the valve flow, separate from the exhaust tail. Silence stays silence.
# Run: godot --headless -s tests/visual/render/intake_sound_test.gd

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: " + msg)


func _init() -> void:
	await process_frame
	var spec := EngineSpec.new()
	var sim := EngineSim.new()
	sim.physics_dt = 1.0 / 2400.0
	var rpm := 3000.0
	for _i in 6:
		sim.omega = rpm * TAU / 60.0
		sim.rpm = rpm
		sim.running = true
		sim.step(0.05, spec, 0.6, true, false, true, false, 1.0)
	var intake := sim.take_intake_flow()
	var energy := 0.0
	for q in intake:
		energy += q * q
	check(intake.size() > 100, "a running engine records intake flow at the audio rate")
	check(energy > 0.0, "the intake flow is not a flat zero")
	var sound := EngineSound.new()
	root.add_child(sound)
	sound.setup(spec)
	var silent := sound.render(2205)
	var silent_energy := 0.0
	for frame in silent:
		silent_energy += frame.x * frame.x
	check(silent_energy == 0.0, "no intake or exhaust flow stays silent")
	sound.push_intake_flow(intake)
	var voiced := sound.render(mini(intake.size(), 4410))
	var voiced_energy := 0.0
	var finite := true
	for frame in voiced:
		voiced_energy += frame.x * frame.x
		if not is_finite(frame.x) or absf(frame.x) > 1.0:
			finite = false
	check(voiced_energy > 0.0, "intake flow alone is audible")
	check(finite, "intake output stays within -1 and 1")
	sound.set_conditions(1.15, 700.0, 140000.0)
	var colored := sound.render(2205)
	var colored_ok := true
	for frame in colored:
		if not is_finite(frame.x) or absf(frame.x) > 1.0:
			colored_ok = false
	check(colored_ok, "lean hot backpressure still stays in range")
	var tip_layout := ExhaustLayout.build(spec)
	var tip := Vector3.ZERO
	for pipe in tip_layout.pipes:
		if pipe.kind == "tail" and not pipe.pts.is_empty():
			tip = pipe.pts[pipe.pts.size() - 1]
	check(tip.length() > 0.5, "the tailpipe tip is a real point the 3D player can sit on")
	sound.free()
	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
