class_name ECU
extends RefCounted

# Engine control unit. It holds the idle speed the way a real bike's ECU does: a PI loop trims the spark advance while
# the throttle is closed. Below the target it advances the spark (more torque), above it retards. Off the idle it lets go.
# Also handles launch control, quickshifter ignition cut, and power mode mapping.

const KP := 0.02 # degrees of advance per rpm below the target
const KI := 0.02 # degrees of advance per rpm of error per second, so a steady error slowly adds advance
const TRIM_MIN := -16.0 # degrees, the most the ECU retards the spark at idle
const TRIM_MAX := 15.0 # degrees, the most the ECU advances the spark at idle
const IDLE_THROTTLE := 0.02 # throttle fraction below which the ECU is in idle control
const ACTIVE_RPM := 300.0 # rpm above which the ECU takes over; just below the firing speed, so a just-fired engine is carried to idle
const RELEASE_RATE := 20.0 # degrees per second the trim fades when the ECU lets go

const KP_AIR := 0.0005 # log units of air per rpm below the target
const KI_AIR := 0.0005 # log units of air per rpm of error per second
const AIR_RELEASE_RATE := 2.0 # log units per second the idle valve returns to neutral when the ECU lets go
const START_BOOST_BELOW := 0.8 # fraction of the idle target below which the start boost applies
const START_BOOST_LOG := 1.5 # log units of extra air at the start boost, about 4.5 times the engine's own idle air
const AIR_LIMIT := 5.0 # log units either way: the idle valve can open or close a long way
const OVERRUN_CUT := 1.7 # closed throttle above this multiple of the idle target cuts the fuel
const OVERRUN_RESUME := 1.25 # fuel returns here, still above the target, so the idle valve can catch it
# Launch control constants
const LAUNCH_RAMP_RATE := 500.0 # rpm/s, how fast the launch RPM target ramps up once moving
const LAUNCH_SLIP_RATE := 0.3 # clutch slip target during launch (0-1)

var target_rpm := 1200.0
var trim := 0.0 # degrees of spark advance added by the ECU right now
var _integral := 0.0
var _air_log := 0.0 # log of the idle-air multiplier: 0 = the engine's own idle air, positive = more air
var _air_integral := 0.0
var manual_air := -1.0 # diagnostics only: when above 0, the idle air is held at this factor
var _overrun := false # closed-throttle fuel cut while the crank is well above idle
# Quickshifter state
var _qs_active := false # true during quickshifter cut
var _qs_timer := 0.0 # remaining cut time
var _speed_limited := false # the speed limiter has closed the throttle and not yet let go
# Quickshifter downshift blip state
var _blip_active := false
var _blip_timer := 0.0
# Launch control state
var _launch_active := false # true when launch control is armed and holding RPM
var _launch_target_rpm := 0.0 # current launch RPM target (ramps up with speed)
# Power mode multipliers
var _power_mode := "F" # "F", "M", "L"
var _power_mode_lambda_mult := 1.0 # lambda target multiplier for current mode
var _power_mode_timing_offset := 0.0 # ignition timing offset for current mode
# Current engine state for QS profile lookup
var _current_rpm: float = 0.0
var _current_gear: int = 0

const POWER_MODE_LAMBDA := {"F": 1.0, "M": 1.02, "L": 1.05} # M/L run slightly leaner for economy
const POWER_MODE_TIMING := {"F": 0.0, "M": -3.0, "L": -6.0} # M/L retard timing for softer delivery

func set_power_mode(mode: String) -> void:
	_power_mode = mode
	_power_mode_lambda_mult = POWER_MODE_LAMBDA.get(mode, 1.0)
	_power_mode_timing_offset = POWER_MODE_TIMING.get(mode, 0.0)

func get_power_mode_lambda_mult() -> float:
	return _power_mode_lambda_mult

func get_power_mode_timing_offset() -> float:
	return _power_mode_timing_offset

func is_quickshifter_active() -> bool:
	return _qs_active

func is_quickshifter_blip_active() -> bool:
	return _blip_active

func is_launch_active() -> bool:
	return _launch_active

func get_launch_target_rpm() -> float:
	return _launch_target_rpm

# Get quickshifter cut time for current RPM and gear (ms -> s)
func _get_qs_cut_time(spec: EngineSpec, gear: int) -> float:
	if spec.quickshifter_cut_profile.is_empty() or gear <= 0 or gear > spec.quickshifter_cut_profile.size():
		return spec.quickshifter_cut_time
	var profile = spec.quickshifter_cut_profile[gear - 1]
	if profile.is_empty():
		return spec.quickshifter_cut_time
	# Linear interpolation between RPM points
	for i in range(profile.size() - 1):
		if _current_rpm >= profile[i][0] and _current_rpm <= profile[i + 1][0]:
			var t = (_current_rpm - profile[i][0]) / (profile[i + 1][0] - profile[i][0])
			return lerp(profile[i][1], profile[i + 1][1], t) / 1000.0
	return profile[-1][1] / 1000.0

# Called once per physics step. Returns throttle override (-1 = no override, 0 = cut, >0 = blip throttle)
func update(dt: float, rpm: float, throttle: float, running: bool, spec: EngineSpec = null, speed_ms: float = 0.0, clutch_pull: float = 0.0, gear: int = 0) -> float:
	_current_rpm = rpm
	_current_gear = gear
	# Disabling an aid must cancel any in-flight intervention on this step.
	if spec == null or not spec.quickshifter or not running:
		_qs_active = false
		_qs_timer = 0.0
		_blip_active = false
		_blip_timer = 0.0
	if spec == null or not spec.launch_control or not running:
		_launch_active = false
		_launch_target_rpm = 0.0
	
	# Quickshifter upshift cut
	if _qs_active:
		_qs_timer -= dt
		if _qs_timer <= 0.0:
			_qs_active = false
		# the ignition and fuel are cut in the sim; the throttle closes, unless flat shift keeps it cracked
		return spec.flat_shift_throttle if spec != null and spec.quickshifter_flat_shift else 0.0
	
	# Quickshifter downshift blip
	if _blip_active:
		_blip_timer -= dt
		if _blip_timer <= 0.0:
			_blip_active = false
		return spec.quickshifter_blip_throttle  # override throttle to blip value
	
	# Speed limiter: closes the throttle at the limit and lets go 2 km/h under it, so the bike holds the limit without chattering
	if spec != null and spec.speed_limit_enabled and running:
		var kmh := speed_ms * 3.6
		if kmh >= spec.speed_limit_kmh:
			_speed_limited = true
		elif kmh < spec.speed_limit_kmh - 2.0:
			_speed_limited = false
		if _speed_limited:
			return 0.0
	else:
		_speed_limited = false

	# Launch control: check if conditions are met to arm/disarm
	if spec != null and spec.launch_control and running:
		var speed_kmh := speed_ms * 3.6
		var launch_armed := throttle >= spec.launch_throttle and clutch_pull > 0.5 and speed_kmh < spec.launch_speed_kmh and rpm < spec.launch_rpm * 1.1
		if launch_armed and not _launch_active:
			_launch_active = true
			_launch_target_rpm = spec.launch_rpm
		elif _launch_active and (speed_kmh >= spec.launch_speed_kmh or throttle < spec.launch_throttle * 0.5 or clutch_pull < 0.2):
			_launch_active = false
		if _launch_active:
			# Ramp up target RPM with speed
			_launch_target_rpm += LAUNCH_RAMP_RATE * dt * clampf(speed_kmh / spec.launch_speed_kmh, 0.0, 1.0)
			_launch_target_rpm = minf(_launch_target_rpm, spec.redline_rpm * 0.95)
	
	# the ECU stays out of the way while the engine is starting and climbing, and only holds the idle once it is running
	if not running or throttle > IDLE_THROTTLE or rpm < ACTIVE_RPM:
		_overrun = false
		if throttle > IDLE_THROTTLE:
			_integral = 0.0 # the idle trim only belongs at a closed throttle: with it left on, a big engine stalls as the throttle opens
		else:
			_integral = move_toward(_integral, 0.0, RELEASE_RATE * dt)
		_air_integral = move_toward(_air_integral, 0.0, AIR_RELEASE_RATE * dt)
		_air_log = _air_integral # the idle valve goes back to the engine's own setting, so a restart is not starved of air
		trim = _integral
		return -1.0  # no throttle override
	
	# A shut throttle still burns enough to hold a larger engine several thousand rpm up. Cut the fuel until it
	# is near idle. The rpm error while cutting is huge, so the valve and the spark stay at a normal idle
	# instead of slamming shut, and the engine can catch when the fuel returns.
	if rpm > target_rpm * OVERRUN_CUT:
		_overrun = true
	elif rpm < target_rpm * OVERRUN_RESUME:
		_overrun = false
	if _overrun:
		# The fuel is cut, so the idle loops hold what they have learned. Letting them drift back to neutral here opened the
		# valve again, and the engine hunted between the cut and the catch instead of settling at the target.
		_air_log = _air_integral
		trim = _integral
		return -1.0
	
	# Launch control overrides idle target when active
	var effective_target := target_rpm
	if _launch_active:
		effective_target = _launch_target_rpm
	
	var error := effective_target - rpm
	# the idle-air valve: below the target it opens, above it closes
	_air_integral = clampf(_air_integral + KI_AIR * error * dt, -AIR_LIMIT, AIR_LIMIT)
	_air_log = clampf(KP_AIR * error + _air_integral, -AIR_LIMIT, AIR_LIMIT)
	# start boost: a just-fired engine is well below the idle speed, so the valve opens wide at once, as an ECU's start air does
	if rpm < effective_target * START_BOOST_BELOW:
		_air_log = maxf(_air_log, START_BOOST_LOG)
	_integral = clampf(_integral + KI * error * dt, TRIM_MIN, TRIM_MAX) # clamped so it cannot wind up
	trim = clampf(KP * error + _integral, TRIM_MIN, TRIM_MAX)
	# Add power mode timing offset
	trim += _power_mode_timing_offset
	return -1.0

# The idle-air multiplier the valve is set to right now.
func air_factor() -> float:
	return manual_air if manual_air > 0.0 else exp(_air_log)

# True while a closed throttle is cutting the fuel because the crank is well above idle.
func overrun() -> bool:
	return _overrun

# Quickshifter upshift: call when rider requests upshift with quickshifter enabled
# Returns true if cut was initiated
func trigger_quickshifter(spec: EngineSpec) -> bool:
	if not spec.quickshifter:
		return false
	_qs_active = true
	_qs_timer = _get_qs_cut_time(spec, _current_gear)
	return true

# Quickshifter downshift: call when rider requests downshift with quickshifter enabled
# Returns true if blip was initiated
func trigger_quickshifter_downshift(spec: EngineSpec) -> bool:
	if not spec.quickshifter:
		return false
	_blip_active = true
	_blip_timer = spec.quickshifter_blip_time
	return true

# Check if quickshifter upshift cut is active (for EngineSim to cut spark+fuel)
func quickshifter_cut_active() -> bool:
	return _qs_active

# Check if quickshifter downshift blip is active
func quickshifter_blip_active() -> bool:
	return _blip_active
