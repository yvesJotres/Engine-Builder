class_name Wheel
extends RefCounted

# One braked wheel: its own angular speed, the slip it is running at, and the grip that follows from it. The simulator
# used to brake the whole bike with one force (EngineSim.BRAKE_FORCE); a wheel that can turn slower than the road is what
# makes a lock-up, and therefore ABS, possible to model at all.
#
# The grip curve is a single peak in slip: it rises to TYRE_MU_PEAK at TYRE_SLIP_PEAK and falls from there, so at 100 %
# slip (a locked wheel) the tyre keeps far less grip than it had at 12 % - which is exactly why a locked front wheel
# takes longer to stop than one the ABS is cycling.

const TYRE_SLIP_PEAK := 0.12 # slip ratio at peak grip; 10-15 % is the textbook figure for a longitudinal tyre
const TYRE_MU_PEAK := 1.05 # peak friction coefficient, dry tarmac on a sports tyre
const TYRE_MU_LOCKED := 0.75 # sliding friction: a locked tyre keeps about 70 % of its peak grip, not a quarter
const MIN_SPEED := 0.5 # m/s, below this a wheel cannot slip meaningfully, so slip is reported as 0

var radius_m := 0.3 # tyre radius, m
var inertia_kgm2 := 0.8 # wheel plus tyre: about 10 kg at a 0.4 m radius of gyration
var omega := 0.0 # wheel angular speed, rad/s
var brake_torque := 0.0 # N·m the caliper is applying this instant
var load_n := 0.0 # vertical load on this wheel, N
var locked_time := 0.0 # s spent at more than twice the peak slip, for the HUD and the tests


# Slip ratio: (wheel speed - road speed) / road speed. Zero when rolling, -1.0 when the wheel is locked.
static func slip_ratio(omega_rad_s: float, speed_m_s: float, radius: float) -> float:
	if speed_m_s < MIN_SPEED:
		return 0.0 # at a crawl a wheel is not locking, it is stopping
	return clampf((omega_rad_s * radius - speed_m_s) / speed_m_s, -1.0, 1.0)


# Friction coefficient at a given slip: rises to the peak, then decays to the sliding value over about a quarter of a
# slip unit. A locked tyre keeps roughly 70 % of its peak grip, which is why a lock-up costs distance but does not
# simply double it.
static func mu(slip: float) -> float:
	var s := absf(slip)
	var k := s / TYRE_SLIP_PEAK
	if k <= 1.0:
		return TYRE_MU_PEAK * (2.0 * k / (1.0 + k * k))
	return TYRE_MU_LOCKED + (TYRE_MU_PEAK - TYRE_MU_LOCKED) * exp(-(s - TYRE_SLIP_PEAK) / 0.25)


# Grip force at the contact patch, N, opposing the direction of travel.
func grip_force() -> float:
	return mu(slip()) * load_n


# Slip this wheel is running at, from the road speed of its last advance().
func slip() -> float:
	return slip_ratio(omega, _speed, radius_m)


# Puts the wheel back in step with the road, for a spawn or a rebuild.
func resync(speed: float) -> void:
	_speed = speed
	omega = speed / maxf(radius_m, 1e-6)
	locked_time = 0.0


# One physics step.
#   speed   road speed, m/s
#   torque  N·m the brake applies, positive
func advance(dt: float, speed: float, torque: float) -> void:
	_speed = speed
	brake_torque = torque
	# the ground reaction slows the wheel by grip * radius; the brake slows it by its torque
	var ground := mu(slip()) * load_n * radius_m
	omega = maxf(omega + (ground - torque) / maxf(inertia_kgm2, 1e-6) * dt, 0.0)
	if speed > MIN_SPEED and absf(slip()) > TYRE_SLIP_PEAK * 2.0:
		locked_time += dt


var _speed := 0.0 # road speed the last advance() used, so slip() needs no arguments
