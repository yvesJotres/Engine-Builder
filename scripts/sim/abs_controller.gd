class_name AbsController
extends RefCounted

# One wheel's anti-lock controller. It reads the slip the wheel is actually running and modulates the caliper torque:
# release fast once slip passes the target, re-apply slowly once it has fallen well below it, hold in between. The slow
# re-apply is the whole trick - a system that re-applies as fast as it releases just re-locks the wheel every cycle and
# stops no shorter than a locked wheel does.
#
# It knows nothing about the bike: give it slip, road speed, the torque it applied last step and the lever's capacity,
# and it returns the torque to apply now.

const RELEASE_SLEW := 60000.0 # N·m/s, pressure dumped: a real ABS opens the valve in about 10 ms
const APPLY_SLEW := 12000.0 # N·m/s, pressure rebuilt - a fifth of the release, as on real systems
const RELEASE_SLIP_FACTOR := 1.15 # slip that starts a release, over the target
const APPLY_SLIP_FACTOR := 0.80 # slip that allows re-apply, under the target

var slip_target := 0.12
var cycle_hz := 8.0
var min_speed_ms := 2.0 # set from the spec's km/h
var cycles := 0 # release events so far (one per modulation cycle), for the HUD and the tests
var active := false # true while it is modulating, i.e. not handing the brake back
var _releasing := false # this step is inside a release, so the next one is not a new cycle


func configure(slip: float, hz: float, min_kmh: float) -> void:
	slip_target = slip
	cycle_hz = hz
	min_speed_ms = min_kmh / 3.6
	cycles = 0
	active = false
	_releasing = false


# Next torque for this wheel.
#   slip      negative under braking, -1.0 locked
#   speed     road speed, m/s
#   torque    torque applied last step, N·m
#   capacity  torque a full lever would apply right now, N·m
func step(dt: float, slip: float, speed: float, torque: float, capacity: float) -> float:
	var s := -slip # work in positive "how much slower than the road" slip
	if speed < min_speed_ms:
		active = false # below a walking pace there is nothing to lock: give the rider the lever
		_releasing = false
		return capacity
	active = true
	var wanted := torque
	if s > slip_target * RELEASE_SLIP_FACTOR:
		if not _releasing:
			cycles += 1 # the start of a release, not every step inside it
			_releasing = true
		wanted = 0.0 # let go completely, as far as the slew allows this step
	else:
		_releasing = false
		if s < slip_target * APPLY_SLIP_FACTOR:
			wanted = capacity
	var slew := RELEASE_SLEW if wanted < torque else APPLY_SLEW
	return move_toward(torque, wanted, slew * dt)
