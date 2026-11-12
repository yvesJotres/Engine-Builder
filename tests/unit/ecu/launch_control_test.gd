extends SceneTree

# Launch control on the ZX-25R. Pulling the lever in at full throttle arms it, and the engine is held at the launch rpm.
# Letting the lever go starts the launch: the clutch slips at its target and the bike pulls away while the rpm stays on
# the target, and the launch ends when the clutch is home. Exits 1 on any failure.
#
# Tightened after an audit found three things wrong, each one pinned below:
#   - the hold was proportional-only in the throttle, so it parked wherever its own output balanced the engine: an 8,000
#     target sat at 8,650 (and the H2R's 9,000 at 9,800). The tolerance is now 2%, not 15%, so the offset cannot return;
#   - the clutch only closed while the engine was ABOVE the target, which is exactly what held the old loop 9% high.
#     With the hold now on the target, the clutch needs its own closing rate or it would never get home;
#   - the launch ended at launch_speed_kmh with the clutch still slipping, which dumps the engine onto the wheel (the
#     H2R went 8,600 -> 4,100 rpm in a quarter second). It now ends on a locked clutch or a gear change.
# Run: godot --headless --path . -s res://tests/unit/ecu/launch_control_test.gd

const DT := 1.0 / 60.0
const RPM_TOLERANCE := 0.02 # the rpm hold must stay within 2% of the target while the lever is in
const LAUNCH_TOLERANCE := 0.05 # through the launch the clutch biting drags the engine a few percent before the loop catches it

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func _init() -> void:
	await process_frame
	var spec := EngineSpec.new()
	var preset: Dictionary = Presets.PRESETS["kawasaki_zx25r"]
	for key in preset.keys():
		spec.set(key, preset[key])
	spec.launch_control = true
	var sim := EngineSim.new()
	sim.audio_enabled = false

	for i in 180:
		sim.step(DT, spec, 0.0, true, true, false, false, 1.0)
	check(sim.running, "the engine starts")
	sim.gear.gear = 1

	# arm: lever in, throttle wide open, until the rpm reaches the launch target
	sim.clutch_pull = 1.0
	var armed := false
	for i in 120:
		sim.step(DT, spec, 1.0, true, false, false, false, 1.0)
		if sim.ecu.is_launch_active():
			armed = true
			break
	check(armed, "pulling the lever in at full throttle arms launch control")
	var target: float = sim.ecu.get_launch_target_rpm()
	for i in 60:
		sim.step(DT, spec, 1.0, true, false, false, false, 1.0)
	check(absf(sim.rpm - target) < target * RPM_TOLERANCE,
		"the rpm settles on the launch target while the lever is in, rpm %.0f target %.0f" % [sim.rpm, target])

	# launch: let the lever go, and the clutch slips while the rpm holds
	sim.clutch_pull = 0.0
	var worst := 0.0
	var ended_at := -1.0
	var speed_at_start: float = sim.speed
	for i in 300:
		sim.step(DT, spec, 1.0, true, false, false, false, 1.0)
		if sim.ecu.is_launch_active():
			# the target ramps up as the bike gains speed, so the hold is measured against the live target
			var live: float = sim.ecu.get_launch_target_rpm()
			worst = maxf(worst, absf(sim.rpm - live) / live)
		elif ended_at < 0.0:
			ended_at = i * DT
	check(worst < LAUNCH_TOLERANCE, "letting the lever go keeps the rpm within %d%% of the target, worst %.1f%%" % [int(LAUNCH_TOLERANCE * 100), worst * 100.0])
	check(sim.speed > speed_at_start + 2.0 / 3.6, "the bike pulls away from the launch, speed %.1f km/h" % (sim.speed * 3.6))
	check(ended_at >= 0.0, "the launch ends, at %.2f s" % ended_at)
	check(sim.clutch_engage > 0.95,
		"it ends with the clutch home (%.2f), not still slipping: an early end dumps the engine onto the wheel" % sim.clutch_engage)

	# ---- the same hold on the bike that really has the system, and from a keyboard ----
	var h2: EngineSpec = DynoRunner.spec_for("kawasaki_h2r")
	check(h2.launch_control, "the H2R preset keeps KLCM")
	var zx_preset: EngineSpec = DynoRunner.spec_for("kawasaki_zx25r_se")
	check(not zx_preset.launch_control and not zx_preset.has_launch_control,
		"the ZX-25R SE preset does not claim KLCM, which Kawasaki does not offer on that bike")
	var hsim := EngineSim.new()
	hsim.fuel.set_kind(h2.fuel)
	for i in 90:
		hsim.step(DT, h2, 0.0, true, i < 60, false, false, 1.0)
	for i in 120:
		hsim.step(DT, h2, 0.0, true, false, false, false, 1.0)
	hsim.gear.gear = 1
	hsim.clutch_pull = 1.0
	for i in 180:
		hsim.step(DT, h2, 1.0, true, false, true, false, 1.0)
	print("H2R hold: rpm %.0f, target %.0f" % [hsim.rpm, h2.launch_rpm])
	check(absf(hsim.rpm - h2.launch_rpm) < h2.launch_rpm * RPM_TOLERANCE,
		"the 9,000 target is held at 9,000, not 9,800 (rpm %.0f)" % hsim.rpm)

	# the clutch key writes the lever the launch reads: without it the feature never armed on a keyboard
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 4:
		await process_frame
	var down := InputEventKey.new()
	down.physical_keycode = KEY_SHIFT
	down.pressed = true
	Input.parse_input_event(down)
	for i in 3:
		await process_frame
	check(main._clutch_held and main._sim.clutch_pull > 0.9,
		"Shift pulls the lever (pull %.2f), so launch control can arm from the keyboard" % main._sim.clutch_pull)
	var up := InputEventKey.new()
	up.physical_keycode = KEY_SHIFT
	up.pressed = false
	Input.parse_input_event(up)
	for i in 3:
		await process_frame
	check(main._sim.clutch_pull < 0.1, "letting the key go lets the lever out (%.2f)" % main._sim.clutch_pull)

	print("launch_control_test: %s" % ("PASSED" if _fails == 0 else "FAILED"))
	quit(0 if _fails == 0 else 1)
