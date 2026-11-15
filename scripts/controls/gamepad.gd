class_name Gamepad
extends RefCounted

# Gamepad input, laid out like a motorcycle's controls rather than a car's:
#
#   right trigger   throttle   analog, the finger's position is the opening
#   left trigger    clutch     analog, 0 = engaged, 1 = pulled in
#   A               brake      (the sim's brake is on/off)
#   RB              upshift
#   LB              downshift
#   Y               starter    hold to crank
#   Start           pause
#   Back            kill switch
#
# The triggers are the reason a pad is worth supporting at all: a key can only ramp, a trigger reports where your
# finger actually is. Every function takes the device id, so one pad is polled per frame.

const TRIGGER_DEADZONE := 0.06 # below this a released trigger reads 0: they rest slightly open and drift
# Trigger travel at which the plates are fully apart, for the starter interlock only. It is deliberately just past the
# end of the friction zone: the sim's clutch_held flag FORCES the clutch open, so taking it any earlier would throw away
# the rest of the analog zone above it (it used to fire at 0.55, which is why the bite only appeared in the last 30 %).
const CLUTCH_FULL := 0.65
# The sim maps lever pull to grip linearly across its whole range (grip is 1.0 until pull 0.5), so feeding it the raw
# trigger would waste the first half of the travel and squeeze the friction zone into the remaining 40 %. These two
# constants put the sim's bite window where a real lever has it: 8 % of travel is free play, the plates slip from there
# to 62 %, and past 62 % they are fully apart. Half a trigger is already most of the way disengaged (22 % grip), because
# on a bike you do not have to bury the lever to cut drive.
const CLUTCH_TRAVEL_BITE_START := 0.08
const CLUTCH_TRAVEL_BITE_END := 0.62
const LEVER_BITE_START := 0.5 # EngineSim.CLUTCH_BITE_START, duplicated here so the mapping reads on its own
const LEVER_BITE_END := 0.9 # EngineSim.CLUTCH_BITE_END

const STARTER_BUTTON := JOY_BUTTON_Y
const PAUSE_BUTTON := JOY_BUTTON_START
const KILL_BUTTON := JOY_BUTTON_BACK

# Which axis the triggers actually live on. The SDL mapping puts them on 4 and 5, and that is what most pads do - but a
# pad that reports its triggers elsewhere (or as a combined Z axis) leaves the throttle dead with no error, which is
# exactly the failure that looks like "the clutch works but the throttle does not". The throttle axis therefore learns
# itself: the first time any axis other than the clutch one is squeezed hard, that axis becomes the throttle.
static var throttle_axis := JOY_AXIS_TRIGGER_RIGHT
static var clutch_axis := JOY_AXIS_TRIGGER_LEFT

const CONFIG_PATH := "user://pad_axes.cfg"


# The first connected gamepad, or -1 when none is attached. Asked every frame, because pads come and go.
#
# A duplicated entry is common on Windows: one device shows up once per transport (XInput + HID, or BLE + classic), and
# one of those entries answers with all zeros forever. Taking pads[0] blindly then means no input at all, which looks
# exactly like a dead controller, so the pad that is actually reporting something wins and the choice is remembered.
static var _last_active := -1


static func device() -> int:
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		_last_active = -1
		return -1
	for p in pads:
		if _pad_has_signal(p):
			_last_active = p
			return p
	if _last_active in pads:
		return _last_active
	return pads[0]


# True when the pad is reporting anything at all: a nonzero axis or any button down.
static func _pad_has_signal(pad: int) -> bool:
	for a in 10:
		if not is_zero_approx(Input.get_joy_axis(pad, a)):
			return true
	for b in 16:
		if Input.is_joy_button_pressed(pad, b):
			return true
	return false


# One trigger axis with its resting noise dropped and the remaining travel spread over the full 0..1 range, so
# 0.06 reads 0 and 1.0 still reads 1.0 - a bare threshold would leave a small step at the bottom and cost range.
static func shape_trigger(raw: float) -> float:
	if raw <= TRIGGER_DEADZONE:
		return 0.0
	return clampf((raw - TRIGGER_DEADZONE) / (1.0 - TRIGGER_DEADZONE), 0.0, 1.0)


static func trigger(pad: int, which: int) -> float:
	if pad < 0:
		return 0.0
	var raw := Input.get_joy_axis(pad, which)
	return shape_trigger(normalize_axis(which, raw))


static func raw_axis(pad: int, axis: int) -> float:
	return 0.0 if pad < 0 else Input.get_joy_axis(pad, axis)


# Axes a trigger can plausibly sit on: SDL puts them on 4 and 5, some pads report a combined or shifted axis after them.
# Sticks are 0-3 and are deliberately not candidates, so pushing a stick can never be learned as a throttle.
const TRIGGER_AXES := [4, 5, 6, 7]


# Adopts the first trigger axis that is squeezed while the configured one sits at rest. Both triggers use the same
# rule, so a pad that reports either of them off-axis fixes itself. The one thing a passive rule cannot know is *which*
# trigger you are squeezing when neither axis is mapped yet - two unknown triggers are indistinguishable without a
# label - so the first one squeezed is taken as the throttle, and the other as the clutch. On a pad where both are
# unknown, squeeze the throttle first.
static func pick_axis(values: Array, configured: int, exclude: int) -> int:
	if configured >= 0 and configured < values.size() and values[configured] > 0.5:
		return -1 # the axis in use is already the right one
	for a in TRIGGER_AXES:
		if a == exclude or a == configured or a >= values.size():
			continue
		if values[a] > 0.5:
			return a
	return -1


# Runs the rule above for both triggers against the live pad. Returns "throttle", "clutch" or "" for no change.
static func learn_axes(pad: int) -> String:
	if pad < 0:
		return ""
	var values := []
	values.resize(8)
	for a in 8:
		values[a] = raw_axis(pad, a)
		note_axis(a, values[a])
	var axis := pick_axis(values, throttle_axis, clutch_axis)
	if axis >= 0:
		throttle_axis = axis
		save_config()
		return "throttle"
	axis = pick_axis(values, clutch_axis, throttle_axis)
	if axis >= 0:
		clutch_axis = axis
		save_config()
		return "clutch"
	return ""


# --- trigger resolution --------------------------------------------------------------------------------------------
# A trigger reported only as 0 or 1 is a switch, not an analog input: no curve can put back travel the pad never sent.
# Every axis read is therefore watched for intermediate values, and once one has been seen fully pressed with none, it
# is treated as digital and the throttle ramps on its hold the way the W key does, instead of slamming to 100 %.
static var _axis_mid: Dictionary = {} # axis -> true once a value between TRIGGER_DEADZONE and 0.6 was seen
static var _axis_peak: Dictionary = {} # axis -> highest value seen
static var _axis_rest: Dictionary = {} # axis -> lowest value seen, i.e. where the control rests


static func note_axis(axis: int, value: float) -> void:
	if value > TRIGGER_DEADZONE and value < 0.6:
		_axis_mid[axis] = true
	_axis_peak[axis] = maxf(float(_axis_peak.get(axis, value)), value)
	_axis_rest[axis] = minf(float(_axis_rest.get(axis, value)), value)


static func reset_axis_tracking() -> void:
	_axis_mid.clear()
	_axis_peak.clear()
	_axis_rest.clear()


# Maps an axis reading onto 0..1 using the range the axis has actually shown, because trigger conventions differ:
# XInput pads rest at 0 and rise to 1, while a DirectInput/HID pad can rest at -1 and rise to +1 (or anywhere in
# between). Assuming "rest is 0" on a pad that rests at -1 makes the trigger look stuck shut for the first half of its
# travel - which is indistinguishable from a broken trigger.
static func normalize_axis(axis: int, value: float) -> float:
	var rest := float(_axis_rest.get(axis, 0.0))
	var peak := float(_axis_peak.get(axis, 1.0))
	if peak - rest < 0.2:
		return maxf(value, 0.0) # not enough evidence yet: fall back to the plain 0..1 reading
	return clampf((value - rest) / (peak - rest), 0.0, 1.0)


# True once the axis has been pressed fully and has never shown a value in between: a 0/1 switch.
static func axis_is_digital(axis: int) -> bool:
	return float(_axis_peak.get(axis, 0.0)) > 0.9 and not bool(_axis_mid.get(axis, false))


static func throttle_is_digital() -> bool:
	return axis_is_digital(throttle_axis)


# 0 = throttle shut, 1 = wide open, tracking the finger in both directions.
static func throttle(pad: int) -> float:
	return shape_trigger(raw_axis(pad, throttle_axis))


# How far the clutch trigger itself is pulled, 0 released to 1 all the way in.
static func clutch_travel(pad: int) -> float:
	return shape_trigger(raw_axis(pad, clutch_axis))


# The trigger's travel turned into the lever pull the sim expects, with its bite window stretched over the travel.
# 0 -> 0 (fully engaged), 1 -> 1 (fully apart), and grip goes from 1 to 0 across CLUTCH_TRAVEL_BITE_START..END.
static func lever_from_travel(travel: float) -> float:
	if travel <= CLUTCH_TRAVEL_BITE_START:
		return 0.0 # lever all the way out: the plates are clamped, and the sim's grip stays 1.0 up to pull 0.5
	var t := clampf((travel - CLUTCH_TRAVEL_BITE_START) / (CLUTCH_TRAVEL_BITE_END - CLUTCH_TRAVEL_BITE_START), 0.0, 1.0)
	return lerpf(LEVER_BITE_START, LEVER_BITE_END, t)


# 0 = clutch engaged, 1 = lever fully in, in sim units: clutch_pull, so it slips by the amount shown.
static func clutch(pad: int) -> float:
	return lever_from_travel(clutch_travel(pad))


# True once the trigger is at the top of its travel, where the plates are apart. For the starter interlock, never for
# driving the sim: the analog pull above is what slips the clutch.
static func clutch_full(pad: int) -> bool:
	return clutch_travel(pad) >= CLUTCH_FULL


static func braking(pad: int) -> bool:
	return pad >= 0 and Input.is_joy_button_pressed(pad, JOY_BUTTON_A)


# -1 for a downshift (LB), 1 for an upshift (RB), 0 for nothing.
static func shift_force(pad: int) -> float:
	if pad < 0:
		return 0.0
	if Input.is_joy_button_pressed(pad, JOY_BUTTON_RIGHT_SHOULDER):
		return 1.0
	if Input.is_joy_button_pressed(pad, JOY_BUTTON_LEFT_SHOULDER):
		return -1.0
	return 0.0


# Y held: the starter turns while it is down, the same as the on-screen button.
static func starter(pad: int) -> bool:
	return pad >= 0 and Input.is_joy_button_pressed(pad, STARTER_BUTTON)


# Shown once when a pad is plugged in, so the rider is not guessing which shoulder does what.
static func mapping_hint() -> String:
	return "GAMEPAD: RT THROTTLE   LT CLUTCH   A BRAKE   RB UPSHIFT   LB DOWNSHIFT   Y START   START PAUSE"


# One line with everything the pad is reporting, for the F9 readout. It names the axis each trigger is being read from,
# so a wrong axis is visible at a glance instead of looking like a dead trigger.
static func describe(pad: int) -> String:
	if pad < 0:
		return "PAD: none connected"
	var axes := PackedStringArray()
	for a in 8:
		var v := raw_axis(pad, a)
		if absf(v) > 0.02:
			axes.append("%d=%.2f" % [a, v])
	var buttons := PackedStringArray()
	for b in 16:
		if Input.is_joy_button_pressed(pad, b):
			buttons.append(str(b))
	return "PAD thr=ax%d %.2f%s  clut=ax%d %.2f  axes[%s] btn[%s]" % [
		throttle_axis, throttle(pad), " DIGITAL" if throttle_is_digital() else "",
		clutch_axis, clutch_travel(pad),
		", ".join(axes), ",".join(buttons)]


static func save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("pad", "throttle_axis", throttle_axis)
	cfg.set_value("pad", "clutch_axis", clutch_axis)
	cfg.save(CONFIG_PATH)


static func load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	throttle_axis = int(cfg.get_value("pad", "throttle_axis", throttle_axis))
	clutch_axis = int(cfg.get_value("pad", "clutch_axis", clutch_axis))
