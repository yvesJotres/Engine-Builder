extends SceneTree

# The gamepad layout is a contract between three files: gamepad.gd, main.gd's polling and the panel's help text.
# These checks pin the parts that broke or would break silently - the button assignments, the no-pad safety, and the
# focus rule that stops the brake (A) from re-pressing whichever panel button was last clicked.
# Run: godot --headless --path . -s tests/unit/controls/gamepad_map_test.gd (prints PASS or FAIL)

var _fails := 0


func _init() -> void:
	await process_frame

	# with no pad plugged in every read is neutral, so a keyboard session never sees a phantom brake or clutch
	check(Gamepad.throttle(-1) == 0.0, "no pad: the throttle reads shut")
	check(Gamepad.clutch(-1) == 0.0, "no pad: the clutch reads released")
	check(not Gamepad.clutch_full(-1), "no pad: the clutch is not pulled in")
	check(not Gamepad.braking(-1), "no pad: no brake")
	check(Gamepad.shift_force(-1) == 0.0, "no pad: no shift")
	check(not Gamepad.starter(-1), "no pad: no starter")

	# the requested layout: RT throttle, LT clutch, A brake, RB upshift, LB downshift
	check(Gamepad.STARTER_BUTTON == JOY_BUTTON_Y, "Y holds the starter")
	check(Gamepad.PAUSE_BUTTON == JOY_BUTTON_START, "Start pauses")
	check(Gamepad.KILL_BUTTON == JOY_BUTTON_BACK, "Back is the kill switch")
	check(Gamepad.mapping_hint().contains("RT THROTTLE"), "the on-screen hint names the throttle trigger")
	check(Gamepad.mapping_hint().contains("RB UPSHIFT"), "the on-screen hint names the upshift shoulder")

	# --- trigger resolution: a trigger is only worth using if its travel is spent on something
	check(Gamepad.shape_trigger(0.0) == 0.0, "a released trigger reads exactly 0")
	check(Gamepad.shape_trigger(Gamepad.TRIGGER_DEADZONE) == 0.0, "the deadzone reads exactly 0")
	check(is_equal_approx(Gamepad.shape_trigger(1.0), 1.0), "a fully pulled trigger still reads 1.0: no range is lost")
	check(Gamepad.shape_trigger(0.081) < 0.03, "just off the deadzone there is no jump")
	var prev := -1.0
	var monotonic := true
	for i in 257:
		var v := Gamepad.shape_trigger(float(i) / 256.0)
		if v < prev:
			monotonic = false
		prev = v
	check(monotonic, "the throttle curve never steps backwards")

	# The sim's lever spends its first half doing nothing (grip is 1.0 until pull 0.5), so the raw trigger would put
	# the whole friction zone into 40 % of the travel. Measured over the pad's 256 steps instead: how many land in it.
	var in_bite := 0
	var grip_prev := 2.0
	var grip_smooth := true
	for i in 256:
		var travel := float(i) / 255.0
		var grip := EngineSim.clutch_grip(Gamepad.lever_from_travel(travel))
		if grip > 0.01 and grip < 0.99:
			in_bite += 1
		if grip > grip_prev + 0.0001:
			grip_smooth = false
		grip_prev = grip
	check(EngineSim.clutch_grip(Gamepad.lever_from_travel(0.0)) > 0.99, "trigger released = clutch fully engaged")
	check(EngineSim.clutch_grip(Gamepad.lever_from_travel(1.0)) < 0.01, "trigger all the way in = clutch fully apart")
	check(grip_smooth, "the clutch grip only ever falls as the trigger goes in")
	check(in_bite >= 120, "the friction zone covers %d of the 255 trigger steps (a raw lever gives 102)" % in_bite)
	# Half a lever must already cut drive - on a bike you do not bury the trigger to disengage - but a quarter pull has
	# to be a real slipping zone, not on/off.
	var half := EngineSim.clutch_grip(Gamepad.lever_from_travel(0.5))
	check(half < 0.35, "half travel is nearly open (%.0f %% grip)" % (half * 100.0))
	var quarter := EngineSim.clutch_grip(Gamepad.lever_from_travel(0.25))
	check(quarter > 0.25 and quarter < 0.95, "a quarter pull is a real slipping zone (%.0f %% grip)" % (quarter * 100.0))
	# the sim forces the plates fully apart when clutch_held is set, so the pad must only ever trip that once the
	# friction zone is finished. At 0.55 - the old threshold - the clutch slammed open and deleted the zone above it.
	check(Gamepad.CLUTCH_FULL >= Gamepad.CLUTCH_TRAVEL_BITE_END,
		"the interlock threshold sits past the friction zone (%.2f)" % Gamepad.CLUTCH_FULL)
	check(EngineSim.clutch_grip(Gamepad.lever_from_travel(Gamepad.CLUTCH_FULL)) < 0.01,
		"at the interlock threshold the plates really are apart")

	# A pad whose trigger is not on axis 5 is the failure that looks like a dead throttle, so both trigger axes are
	# learnable by the same rule and remembered. Sticks (0-3) must never be learned as a trigger.
	check(not Gamepad.TRIGGER_AXES.has(0) and not Gamepad.TRIGGER_AXES.has(3), "sticks are never learned as triggers")
	check(Gamepad.TRIGGER_AXES.has(Gamepad.throttle_axis), "the default throttle axis is a candidate")
	check(Gamepad.TRIGGER_AXES.has(Gamepad.clutch_axis), "the default clutch axis is a candidate")
	# the learning rule, driven with fake axis values so it is testable without hardware
	var dead := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var rt_on_6 := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.97, 0.0]
	var lt_on_7 := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.9]
	check(Gamepad.pick_axis(rt_on_6, 5, 4) == 6, "a trigger squeezed off-axis is adopted")
	check(Gamepad.pick_axis(rt_on_6, 5, 6) == -1, "the other trigger's axis is never stolen")
	check(Gamepad.pick_axis(lt_on_7, 6, 6) == 7, "the clutch learns by the same rule")
	check(Gamepad.pick_axis(dead, 5, 4) == -1, "nothing squeezed changes nothing")
	var live := [0.0, 0.0, 0.0, 0.0, 0.0, 0.93, 0.0, 0.0]
	check(Gamepad.pick_axis(live, 5, 4) == -1, "an axis that already works is left alone")
	var keep := Gamepad.throttle_axis
	Gamepad.save_config()
	Gamepad.throttle_axis = 7
	Gamepad.load_config()
	check(Gamepad.throttle_axis == keep, "the learned axis survives a save/load round trip")
	Gamepad.throttle_axis = keep
	check(Gamepad.describe(-1).contains("none"), "the F9 readout copes with no pad plugged in")

	# a switch-shaped trigger must be recognised so the throttle ramps instead of slamming 0 -> 100 % in one frame
	Gamepad.reset_axis_tracking()
	Gamepad.note_axis(9, 0.0)
	Gamepad.note_axis(9, 1.0)
	Gamepad.note_axis(9, 0.0)
	check(Gamepad.axis_is_digital(9), "an axis that only ever reads 0 or 1 is digital")
	Gamepad.reset_axis_tracking()
	for v in [0.0, 0.31, 0.62, 1.0, 0.44]:
		Gamepad.note_axis(9, v)
	check(not Gamepad.axis_is_digital(9), "an axis with intermediate values is analog")
	Gamepad.reset_axis_tracking()
	Gamepad.note_axis(9, 0.0)
	check(not Gamepad.axis_is_digital(9), "an axis that was never pressed is not called digital")
	Gamepad.reset_axis_tracking()

	# triggers rest at 0 on XInput pads but at -1 on some DirectInput/HID pads: the mapping must use the real range,
	# otherwise a bipolar trigger looks shut for the first half of its travel
	Gamepad.note_axis(5, -1.0)
	Gamepad.note_axis(5, -1.0)
	Gamepad.note_axis(5, 1.0)
	check(absf(Gamepad.normalize_axis(5, -1.0)) < 0.01, "a bipolar axis at rest reads 0")
	check(absf(Gamepad.normalize_axis(5, 0.0) - 0.5) < 0.01, "a bipolar axis at the middle reads half")
	check(absf(Gamepad.normalize_axis(5, 1.0) - 1.0) < 0.01, "a bipolar axis fully pressed reads 1")
	Gamepad.reset_axis_tracking()
	Gamepad.note_axis(5, 0.0)
	Gamepad.note_axis(5, 1.0)
	check(absf(Gamepad.normalize_axis(5, 0.5) - 0.5) < 0.01, "a 0..1 axis is left as it is")
	Gamepad.reset_axis_tracking()

	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 6:
		await process_frame
	main.set_process(false)

	# A is both the brake and Godot's ui_accept: any button that kept the focus would fire every time the brake was
	# squeezed, which is how a rider would delete a build or reload a preset mid-corner.
	var offenders: Array = []
	_collect_focusable(main._panel, offenders)
	check(offenders.is_empty(), "no panel button keeps the focus (A is the brake): %s" % [offenders])

	print("RESULT: " + ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(1 if _fails > 0 else 0)


func _collect_focusable(node: Node, out: Array) -> void:
	if node is BaseButton and (node as BaseButton).focus_mode != Control.FOCUS_NONE:
		out.append(str(node.get("text")))
	for child in node.get_children():
		_collect_focusable(child, out)


func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1
