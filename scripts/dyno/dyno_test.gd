class_name DynoTest
extends RefCounted

# The automatic dyno test. It starts the engine in neutral, lets it warm at idle, then runs wide open through every gear in
# turn, shifting at the redline, and records the crank torque at each rpm. The rider's inputs (starter, throttle, clutch,
# gearbox) are driven here, and the engine runs through the same physics as a ride (EngineSim.step), so the readings are
# the engine's own output.

const BIN_RPM := 250.0 # rpm per point on the curve
const MIN_SAMPLES := 20 # physics steps a point needs before it counts
const START_LIMIT := 15.0 # s to start the engine
const HOLDS_RPM := 1000.0 # rpm the engine must reach on its own before the starter is let go, or it stalls back down
const WARM_TIME := 3.0 # s at idle before the first gear
const SHIFT_TIME := 0.4 # s the clutch is held in while the gear changes
const LAUNCH_TIME := 1.5 # s the lever takes to come out in first gear, so the bike launches without stalling
const ENGAGE_TIME := 0.6 # s the lever takes to come out in the other gears
const GEAR_LIMIT := 40.0 # s, the longest one gear may run
const PLATEAU_AFTER := 8.0 # s in a gear before the speed is checked for having stopped rising
const PLATEAU_WINDOW := 2.0 # s over which the rpm must rise
const PLATEAU_RPM := 100.0 # rpm the engine must gain over the window to count as still accelerating
const SHIFT_AT := 0.97 # share of the redline where the rider shifts up
const KW_PER_HP := 0.7457

enum Phase { IDLE, START, WARM, SHIFT, PULL, DONE }

var phase := Phase.IDLE
var throttle := 0.0 # the throttle the rider holds, 0 to 1
var clutch_held := false # the Shift key: clutch fully pulled in
var clutch_pull := 0.0 # the clutch lever, 0 engaged to 1 pulled in
var status := ""
var ok := true
var rpm_now := 0.0

var _starter := false
var _phase_time := 0.0
var _gear := 0 # the gear being run
var _ramp := ENGAGE_TIME # s the lever takes to come out in the current gear
var _redline := 10600.0
var _bins := 1
var _sum_torque := PackedFloat64Array() # per gear and bin, index gear * _bins + bin
var _sum_rpm := PackedFloat64Array()
var _count := PackedFloat64Array()
var _window_t := 0.0
var _window_rpm := 0.0
var _accumulator := 0.0


func active() -> bool:
	return phase != Phase.IDLE and phase != Phase.DONE


func redline() -> float:
	return _redline


func status_text() -> String:
	return status if not active() else "%s   %d rpm" % [status, roundi(rpm_now)]


# Starts the test from the engine as it stands. Neutral is selected first, then the starter cranks the engine.
func start(spec: EngineSpec, sim: EngineSim) -> void:
	_redline = spec.redline_rpm
	_bins = int(ceil(_redline / BIN_RPM)) + 1
	_sum_torque = _zeros((Gearbox.TOP_GEAR + 1) * _bins)
	_sum_rpm = _zeros((Gearbox.TOP_GEAR + 1) * _bins)
	_count = _zeros((Gearbox.TOP_GEAR + 1) * _bins)
	while sim.gear.gear != 0:
		sim.gear.shift_down()
	phase = Phase.START
	_phase_time = 0.0
	_accumulator = 0.0
	ok = true
	rpm_now = sim.rpm
	status = "Starting the engine"
	throttle = 0.0
	clutch_held = false
	clutch_pull = 0.0
	_starter = true


# Stops the test where it stands. The curve so far stays on the screen.
func cancel() -> void:
	if active():
		_fail("Stopped by the rider")


# Runs the test for one frame of delta seconds, in the same fixed physics steps as a ride.
func advance(delta: float, sim: EngineSim, spec: EngineSpec, lambda: float, ignition: bool) -> void:
	if not active():
		return
	var dt := sim.physics_dt
	_accumulator = minf(_accumulator + delta, EngineSim.MAX_FRAME_TIME)
	while _accumulator >= dt and active():
		_accumulator -= dt
		_tick(dt, sim, spec, lambda, ignition)


# The curve and the peaks so far. Each point is the average over every gear that reached that rpm.
func result() -> Dictionary:
	var curve := []
	var peak_torque := {"torque": 0.0, "rpm": 0.0}
	var peak_hp := {"hp": 0.0, "rpm": 0.0, "torque": 0.0}
	for b in _bins:
		var sum_t := 0.0
		var sum_r := 0.0
		var n := 0.0
		for g in range(1, Gearbox.TOP_GEAR + 1):
			var i: int = g * _bins + b
			sum_t += _sum_torque[i]
			sum_r += _sum_rpm[i]
			n += _count[i]
		if n < MIN_SAMPLES:
			continue
		var torque := sum_t / n
		var rpm := sum_r / n
		var hp := Units.w_to_hp(Units.power_w(torque, rpm))
		curve.append({"rpm": rpm, "torque": torque, "hp": hp})
		if torque > peak_torque.torque:
			peak_torque = {"torque": torque, "rpm": rpm}
		if hp > peak_hp.hp:
			peak_hp = {"hp": hp, "rpm": rpm, "torque": torque}
	var gears := []
	for g in range(1, Gearbox.TOP_GEAR + 1):
		var gear_torque := {"torque": 0.0, "rpm": 0.0}
		var gear_hp := {"hp": 0.0, "rpm": 0.0}
		var samples := 0.0
		for b in _bins:
			var i: int = g * _bins + b
			var n: float = _count[i]
			samples += n
			if n < MIN_SAMPLES:
				continue
			var torque := _sum_torque[i] / n
			var rpm := _sum_rpm[i] / n
			var hp := Units.w_to_hp(Units.power_w(torque, rpm))
			if torque > gear_torque.torque:
				gear_torque = {"torque": torque, "rpm": rpm}
			if hp > gear_hp.hp:
				gear_hp = {"hp": hp, "rpm": rpm}
		gears.append({"gear": g, "torque": gear_torque.torque, "torque_rpm": gear_torque.rpm, "hp": gear_hp.hp, "hp_rpm": gear_hp.rpm, "samples": samples})
	return {"curve": curve, "peak_torque": peak_torque, "peak_hp": peak_hp, "gears": gears, "ok": ok, "status": status}


# One physics step: the rider's inputs for this moment, then the engine moves, then the readings are taken.
func _tick(dt: float, sim: EngineSim, spec: EngineSpec, lambda: float, ignition: bool) -> void:
	if not ignition:
		_fail("The kill switch was turned off")
		return
	_phase_time += dt
	_control(sim)
	if not active():
		return
	sim.clutch_pull = clutch_pull
	sim.step(dt, spec, throttle, true, _starter, clutch_held, false, lambda)
	rpm_now = sim.rpm
	_observe(sim)


# Sets the rider's inputs for the current phase, and moves to the next phase when its time is up.
func _control(sim: EngineSim) -> void:
	match phase:
		Phase.START:
			throttle = 0.0
			clutch_held = false
			clutch_pull = 0.0
			_starter = true
			if sim.running and sim.rpm >= HOLDS_RPM:
				_starter = false
				phase = Phase.WARM
				_phase_time = 0.0
				status = "Warming up at idle"
			elif _phase_time > START_LIMIT:
				_fail("The engine did not start")
		Phase.WARM:
			throttle = 0.0
			clutch_held = false
			clutch_pull = 0.0
			_starter = false
			if not sim.running:
				_fail("The engine stalled at idle")
			elif _phase_time >= WARM_TIME:
				_begin_gear(1, sim)
		Phase.SHIFT:
			throttle = 0.0
			clutch_held = true
			clutch_pull = 1.0
			if _phase_time >= SHIFT_TIME:
				phase = Phase.PULL
				_phase_time = 0.0
				_window_t = 0.0
				_window_rpm = sim.rpm
				status = "Gear %d" % _gear
		Phase.PULL:
			# wide open, and the lever comes out over the ramp time so the clutch takes up without stalling
			throttle = 1.0
			clutch_held = false
			clutch_pull = maxf(1.0 - _phase_time / _ramp, 0.0)


# Takes a reading from a physics step with the clutch fully engaged and the throttle open. Then checks whether the gear is done.
func _observe(sim: EngineSim) -> void:
	if phase != Phase.PULL:
		return
	if not sim.running:
		_fail("The engine stalled in gear %d" % _gear)
		return
	if clutch_pull <= 0.0 and sim.clutch_engage > 0.99 and not sim.limiter_active:
		_record(sim)
	_check_gear_end(sim)


func _check_gear_end(sim: EngineSim) -> void:
	# the redline counts only once the clutch has taken up: right after a shift the engine still spins at the old gear's rpm
	var at_redline := sim.clutch_engage > 0.99 and sim.rpm >= _redline * SHIFT_AT
	if _phase_time >= GEAR_LIMIT or at_redline:
		_next_gear(sim)
	elif _phase_time - _window_t >= PLATEAU_WINDOW:
		# the bike has stopped gaining speed in this gear (top gear, at its top speed), so there is nothing more to read
		if _phase_time > PLATEAU_AFTER and sim.rpm - _window_rpm < PLATEAU_RPM:
			_next_gear(sim)
		else:
			_window_t = _phase_time
			_window_rpm = sim.rpm


func _record(sim: EngineSim) -> void:
	var b := clampi(int(sim.rpm / BIN_RPM), 0, _bins - 1)
	var i: int = _gear * _bins + b
	_sum_torque[i] += sim.torque
	_sum_rpm[i] += sim.rpm
	_count[i] += 1.0


func _next_gear(sim: EngineSim) -> void:
	if _gear >= Gearbox.TOP_GEAR:
		_finish()
	else:
		_begin_gear(_gear + 1, sim)


func _begin_gear(gear: int, sim: EngineSim) -> void:
	_gear = gear
	_shift_to(sim.gear, gear)
	_ramp = LAUNCH_TIME if gear == 1 else ENGAGE_TIME
	phase = Phase.SHIFT
	_phase_time = 0.0
	status = "Shifting to gear %d" % gear


func _finish() -> void:
	phase = Phase.DONE
	throttle = 0.0
	clutch_held = false
	clutch_pull = 0.0
	status = "Dyno test complete"


func _fail(message: String) -> void:
	phase = Phase.DONE
	ok = false
	throttle = 0.0
	clutch_held = false
	clutch_pull = 0.0
	status = message


# Moves the drum to the wanted gear the way a rider does: each press goes one step, and neutral sits between 1st and 2nd.
static func _shift_to(gear: Gearbox, target: int) -> void:
	var presses := 0
	while gear.gear != target and presses < 20:
		if (gear.gear == 0 and target == 1) or gear.gear > target:
			gear.shift_down()
		else:
			gear.shift_up()
		presses += 1


static func _zeros(size: int) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(size)
	for i in size:
		out[i] = 0.0
	return out
