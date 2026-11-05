class_name ECU
extends RefCounted

# Engine control unit. It holds the idle speed the way a real bike's ECU does: a PI loop trims the spark advance while
# the throttle is closed. Below the target it advances the spark (more torque), above it retards. Off the idle it lets go.

const KP := 0.02 # degrees of advance per rpm below the target
const KI := 0.02 # degrees of advance per rpm of error per second, so a steady error slowly adds advance
const TRIM_MIN := -8.0 # degrees, the most the ECU retards the spark at idle
const TRIM_MAX := 15.0 # degrees, the most the ECU advances the spark at idle
const IDLE_THROTTLE := 0.02 # throttle fraction below which the ECU is in idle control
const ACTIVE_RPM := 300.0 # rpm above which the ECU takes over; just below the firing speed, so a just-fired engine is carried to idle
const RELEASE_RATE := 20.0 # degrees per second the trim fades when the ECU lets go

var target_rpm := 1200.0
var trim := 0.0 # degrees of spark advance added by the ECU right now
var _integral := 0.0
var _air_log := 0.0 # log of the idle-air multiplier: 0 = the engine's own idle air, positive = more air
var _air_integral := 0.0

const KP_AIR := 0.0005 # log units of air per rpm below the target
const KI_AIR := 0.0005 # log units of air per rpm of error per second
const AIR_RELEASE_RATE := 2.0 # log units per second the idle valve returns to neutral when the ECU lets go
const START_BOOST_BELOW := 0.8 # fraction of the idle target below which the start boost applies
const START_BOOST_LOG := 1.5 # log units of extra air at the start boost, about 4.5 times the engine's own idle air
const AIR_LIMIT := 5.0 # log units either way: the idle valve can open or close a long way


# Called once per physics step. Returns the spark advance trim in degrees.
func update(dt: float, rpm: float, throttle: float, running: bool) -> float:
	# the ECU stays out of the way while the engine is starting and climbing, and only holds the idle once it is running
	if not running or throttle > IDLE_THROTTLE or rpm < ACTIVE_RPM:
		_integral = move_toward(_integral, 0.0, RELEASE_RATE * dt)
		_air_integral = move_toward(_air_integral, 0.0, AIR_RELEASE_RATE * dt)
		_air_log = _air_integral # the idle valve goes back to the engine's own setting, so a restart is not starved of air
		trim = _integral
		return trim
	var error := target_rpm - rpm
	# the idle-air valve: below the target it opens, above it closes
	_air_integral = clampf(_air_integral + KI_AIR * error * dt, -AIR_LIMIT, AIR_LIMIT)
	_air_log = clampf(KP_AIR * error + _air_integral, -AIR_LIMIT, AIR_LIMIT)
	# start boost: a just-fired engine is well below the idle speed, so the valve opens wide at once, as an ECU's start air does
	if rpm < target_rpm * START_BOOST_BELOW:
		_air_log = maxf(_air_log, START_BOOST_LOG)
	_integral = clampf(_integral + KI * error * dt, TRIM_MIN, TRIM_MAX) # clamped so it cannot wind up
	trim = clampf(KP * error + _integral, TRIM_MIN, TRIM_MAX)
	return trim


# The idle-air multiplier the valve is set to right now.
func air_factor() -> float:
	return exp(_air_log)
