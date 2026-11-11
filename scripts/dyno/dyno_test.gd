class_name DynoTest
extends RefCounted

signal shift_pedal_requested(up: bool)

# The automatic dyno test. It starts the engine, eases the clutch out in first gear at a closed throttle so the pull
# begins near idle, then runs wide open to the redline. An upshift closes the throttle and opens the clutch before the
# drum moves, so the engine is never free-revved and the curve is not missing its bottom end.

const BIN_RPM := 250.0 # rpm per point on the curve
const MIN_SAMPLES := 2 # independent complete engine cycles per bin
const START_LIMIT := 15.0 # s to start the engine
const HOLDS_RPM := 1000.0 # rpm the engine must reach on its own before the starter is let go, or it stalls back down
const WARM_TIME := 1.5 # s at idle before first gear is selected
const TAKEUP_LIMIT := 12.0 # s to get the clutch fully home in first without the engine flaring
const SHIFT_LIMIT := 4.0 # s for one upshift: throttle shut, clutch open, click, clutch home
const GEAR_LIMIT := 40.0 # s, the longest one gear may run
const TOP_GEAR_LIMIT := 120.0 # allow a power-limited road run to settle in top gear
const PLATEAU_AFTER := 8.0 # s in a gear before the speed is checked for having stopped rising
const PLATEAU_WINDOW := 2.0 # s over which the rpm must rise
const PLATEAU_RPM := 100.0 # rpm the engine must gain over the window to count as still accelerating
const SHIFT_AT := 0.999 # share of the redline where the rider shifts up: at the redline, same as top gear
const BITE_RATE := 0.28 # lever travel per second while the clutch is taking up, slow enough to leave the engine near idle
# The rider's hand cannot jump. The command sets where the throttle and lever are heading, and they move at these rates.
const THROTTLE_OPEN_RATE := 5.0 # per s: roll on to wide open in about 0.2 s, so the first full-throttle reading stays near idle
const THROTTLE_CLOSE_RATE := 4.0 # per s: shut in about 0.25 s
const CLUTCH_PULL_RATE := 6.0 # lever per s: pulled in about 0.17 s
const CLUTCH_RELEASE_RATE := 3.0 # lever per s when let out; the take-up itself is still governed by BITE_RATE
const KW_PER_HP := 0.7457
# Physics steps a second during a sweep. Kept at the game rate: 1200 was only 22% faster and moved peak torque by 5%.
const SWEEP_STEPS_PER_SECOND := 2400.0

enum Phase { IDLE, START, WARM, CLUTCH, TAKEUP, PULL, UPSHIFT, DONE }

var phase := Phase.IDLE
var throttle := 0.0 # the throttle the rider holds, 0 to 1
var clutch_held := false # the Shift key: clutch fully pulled in
var clutch_pull := 0.0 # the clutch lever, 0 engaged to 1 pulled in
var status := ""
var ok := true
var rpm_now := 0.0
var _spec: EngineSpec
var reference_id := "" # stable library ID, supplied by the source UI

var _starter := false
var _phase_time := 0.0
var _gear := 0 # the gear being run
var _clicked := false # the upshift's drum click has happened, with the clutch already open
var _pull_deg := 0.0 # crank degrees since this gear went wide open, so the first recorded cycle is at full throttle
var _redline := 10600.0
var _gear_count := 6
var max_gears := 0 # 0 runs every gear. 1 is the smoke test: first gear only
var _bins := 1
var _shift_at := SHIFT_AT
var _shift_style := "clutch"
var _bite_rate := BITE_RATE
var _plateau_rpm := PLATEAU_RPM
var _plateau_after := PLATEAU_AFTER
var _misses := 0
var _ambient_p := 101325.0
var _ambient_t := 300.0
var _ambient_h := 0.0
var _oil_c := 100.0
var _coolant_c := 90.0
var _max_speed := PackedFloat64Array() # m/s, the fastest the bike actually went in each gear
var _max_speed_rpm := PackedFloat64Array() # engine rpm when the fastest speed in each gear was reached
var _slip_n := PackedFloat64Array() # wide-open samples per gear with a slip reading
var _slip_sum := PackedFloat64Array() # sum of engine-minus-wheel rpm per gear
var _slip_peak := PackedFloat64Array() # largest engine-over-wheel slip per gear, rpm
var _slip_pct_peak := PackedFloat64Array() # slip at that peak, % of engine rpm
var _gear_end: Array = [] # why each gear ended: limiter, plateau or time_limit
var _sent_throttle := 0.0 # throttle last sent to the engine, after the rider's rate limit
var _sent_clutch := 0.0 # clutch lever last sent to the engine, after the rider's rate limit
var _sum_torque := PackedFloat64Array() # per gear and bin, index gear * _bins + bin
var _sum_sq := PackedFloat64Array()
var _sum_rpm := PackedFloat64Array()
var _sum_fuel := PackedFloat64Array() # g/s
var _sum_lambda := PackedFloat64Array()
var _sum_egt := PackedFloat64Array() # °C
var _sum_imap := PackedFloat64Array() # Pa
var _count := PackedFloat64Array()
var _window_t := 0.0
var _window_rpm := 0.0
var _accumulator := 0.0
var _sim_ref: EngineSim # the sim whose step size the sweep changed
var _saved_dt := 0.0 # the step size to restore when the sweep ends
var _last_cycle := -1
var _roller_run := false
var _end_reason := "not_finished"


func active() -> bool:
	return phase != Phase.IDLE and phase != Phase.DONE


func redline() -> float:
	return _redline


func status_text() -> String:
	return status if not active() else "%s   %d rpm" % [status, roundi(rpm_now)]


# Starts the test from the engine as it stands. Neutral is selected first, then the starter cranks the engine.
func start(spec: EngineSpec, sim: EngineSim) -> void:
	_spec = spec
	_redline = spec.redline_rpm
	_gear_count = spec.gear_ratios.size()
	_bins = int(ceil(_redline / BIN_RPM)) + 1
	var cells := (_gear_count + 1) * _bins
	_sum_torque = _zeros(cells)
	_sum_sq = _zeros(cells)
	_sum_rpm = _zeros(cells)
	_sum_fuel = _zeros(cells)
	_sum_lambda = _zeros(cells)
	_sum_egt = _zeros(cells)
	_sum_imap = _zeros(cells)
	_count = _zeros(cells)
	_max_speed = _zeros(_gear_count + 1)
	_max_speed_rpm = _zeros(_gear_count + 1)
	_slip_n = _zeros(_gear_count + 1)
	_slip_sum = _zeros(_gear_count + 1)
	_slip_peak = _zeros(_gear_count + 1)
	_slip_pct_peak = _zeros(_gear_count + 1)
	_gear_end = []
	_gear_end.resize(_gear_count + 1)
	_gear_end.fill("")
	_ambient_p = spec.ambient_pressure_pa
	_ambient_t = spec.ambient_temp_k
	_ambient_h = spec.relative_humidity
	_shift_at = spec.dyno_shift_fraction if spec.dyno_shift_fraction > 0.0 else SHIFT_AT
	_shift_at *= lerpf(0.9, 1.0, clampf(spec.dyno_rider_skill, 0.0, 1.0))
	_shift_style = spec.dyno_shift_style
	_bite_rate = BITE_RATE * clampf(spec.dyno_rider_skill, 0.3, 1.0)
	_plateau_rpm = spec.dyno_plateau_rpm if spec.dyno_plateau_rpm > 0.0 else maxf(40.0, _redline * 0.004)
	_plateau_after = spec.dyno_plateau_after if spec.dyno_plateau_after > 0.0 else PLATEAU_AFTER
	_sim_ref = sim
	_saved_dt = sim.physics_dt
	# A sweep needs at least the normal rate, but must honour a player's more
	# accurate setting instead of silently reducing it to 2400 Hz.
	sim.physics_dt = minf(sim.physics_dt, 1.0 / SWEEP_STEPS_PER_SECOND)
	# First gear has no lower detent; repeatedly shifting down from it never reaches neutral.
	sim.gear.gear = 0
	_last_cycle = sim.cycle_index
	_roller_run = sim.cell_mass_kg > 0.0
	_end_reason = "not_finished"
	phase = Phase.START
	_phase_time = 0.0
	_accumulator = 0.0
	ok = true
	rpm_now = sim.rpm
	status = "Starting the engine"
	throttle = 0.0
	clutch_held = false
	clutch_pull = 0.0
	_sent_throttle = 0.0
	_sent_clutch = 0.0
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
# Torque and power stay as measured. corrected_* is the same reading brought to the SAE J1349 day.
func result() -> Dictionary:
	var factor := sae_j1349_factor(_ambient_p, _ambient_t, _ambient_h)
	var curve := []
	var peak_torque := {"torque": 0.0, "rpm": 0.0, "corrected": 0.0, "stdev": 0.0, "samples": 0.0}
	var peak_hp := {"hp": 0.0, "rpm": 0.0, "torque": 0.0, "corrected": 0.0, "stdev": 0.0, "samples": 0.0}
	for b in _bins:
		var point := _merge_bin(b, factor)
		if point.is_empty():
			continue
		curve.append(point)
		if float(point.torque) > float(peak_torque.torque):
			peak_torque = {"torque": point.torque, "rpm": point.rpm, "corrected": point.corrected_torque, "stdev": point.torque_stdev, "samples": point.samples}
		if float(point.hp) > float(peak_hp.hp):
			peak_hp = {"hp": point.hp, "rpm": point.rpm, "torque": point.torque, "corrected": point.corrected_hp, "stdev": point.torque_stdev, "samples": point.samples}
	var gears := []
	for g in range(1, _gear_count + 1):
		var gear_torque := {"torque": 0.0, "rpm": 0.0}
		var gear_hp := {"hp": 0.0, "rpm": 0.0}
		var samples := 0.0
		var pull := [] # this gear's own pull, one point per bin, before any averaging across gears
		for b in _bins:
			var i: int = g * _bins + b
			var n: float = _count[i]
			samples += n
			if n < MIN_SAMPLES:
				continue
			var torque := _sum_torque[i] / n
			var rpm := _sum_rpm[i] / n
			var hp := Units.w_to_hp(Units.power_w(torque, rpm))
			pull.append({"rpm": rpm, "torque": torque, "hp": hp})
			if torque > gear_torque.torque:
				gear_torque = {"torque": torque, "rpm": rpm}
			if hp > gear_hp.hp:
				gear_hp = {"hp": hp, "rpm": rpm}
		var slip_mean := _slip_sum[g] / _slip_n[g] if _slip_n[g] > 0.0 else 0.0
		gears.append({"gear": g, "curve": pull, "torque": gear_torque.torque, "torque_rpm": gear_torque.rpm, "hp": gear_hp.hp, "hp_rpm": gear_hp.rpm,
			"kmh": _max_speed[g] * 3.6, "top_kmh_rpm": _max_speed_rpm[g], "samples": samples,
			"slip_samples": _slip_n[g], "slip_rpm_mean": slip_mean, "slip_rpm_peak": _slip_peak[g], "slip_pct_peak": _slip_pct_peak[g],
			"end_reason": _gear_end[g]})
	return {
		"curve": curve, "peak_torque": peak_torque, "peak_hp": peak_hp, "gears": gears, "ok": ok, "status": status,
		"sae_factor": factor,
		"ambient": {"pressure_pa": _ambient_p, "temp_k": _ambient_t, "relative_humidity": _ambient_h},
		"oil_c": _oil_c, "coolant_c": _coolant_c,
		"speed_kind": "roller" if _roller_run else "road",
		"speed_end_reason": _end_reason,
		"sample_basis": "independent complete engine cycles; estimated crank output",
		"reference_id": reference_id,
	}


# One rpm bin averaged across every gear that sampled it. Empty when fewer than MIN_SAMPLES landed there.
func _merge_bin(b: int, factor: float) -> Dictionary:
	var sum_t := 0.0
	var sum_sq := 0.0
	var sum_r := 0.0
	var sum_fuel := 0.0
	var sum_lambda := 0.0
	var sum_egt := 0.0
	var sum_imap := 0.0
	var n := 0.0
	for g in range(1, _gear_count + 1):
		var i: int = g * _bins + b
		sum_t += _sum_torque[i]
		sum_sq += _sum_sq[i]
		sum_r += _sum_rpm[i]
		sum_fuel += _sum_fuel[i]
		sum_lambda += _sum_lambda[i]
		sum_egt += _sum_egt[i]
		sum_imap += _sum_imap[i]
		n += _count[i]
	if n < MIN_SAMPLES:
		return {}
	var torque := sum_t / n
	var rpm := sum_r / n
	var hp := Units.w_to_hp(Units.power_w(torque, rpm))
	var power_kw := hp * KW_PER_HP
	var variance := maxf(sum_sq / n - torque * torque, 0.0)
	return {
		"rpm": rpm, "torque": torque, "hp": hp,
		"corrected_torque": torque * factor, "corrected_hp": hp * factor,
		"bsfc_g_kwh": sum_fuel / n * 3600.0 / power_kw if power_kw > 0.05 else 0.0,
		"lambda": sum_lambda / n, "egt_c": sum_egt / n, "intake_pa": sum_imap / n,
		"torque_stdev": sqrt(variance), "samples": n,
	}


# One physics step: the rider's inputs for the current phase, and moves to the next phase when its time is up.
func _tick(dt: float, sim: EngineSim, spec: EngineSpec, lambda: float, ignition: bool) -> void:
	if not ignition:
		_fail("The kill switch was turned off")
		return
	_phase_time += dt
	_control(dt, sim, spec)
	if not active():
		return
	# the rider's hand moves at a finite rate, so the throttle and clutch lever ramp instead of stepping
	throttle = move_toward(_sent_throttle, throttle, (THROTTLE_OPEN_RATE if throttle > _sent_throttle else THROTTLE_CLOSE_RATE) * dt)
	clutch_pull = move_toward(_sent_clutch, clutch_pull, (CLUTCH_PULL_RATE if clutch_pull > _sent_clutch else CLUTCH_RELEASE_RATE) * dt)
	_sent_throttle = throttle
	_sent_clutch = clutch_pull
	sim.clutch_pull = clutch_pull
	sim.step(dt, spec, throttle, true, _starter, clutch_held, false, lambda)
	rpm_now = sim.rpm
	_oil_c = sim.oil_c
	_coolant_c = sim.coolant_c
	_note_speed(sim)
	_observe(dt, sim)


# Sets the rider's inputs for the current phase, and moves to the next phase when its time is up.
func _control(dt: float, sim: EngineSim, spec: EngineSpec) -> void:
	_starter = false
	clutch_held = false
	match phase:
		Phase.START:
			throttle = 0.0
			clutch_pull = 0.0
			_starter = true
			if sim.running and sim.rpm >= HOLDS_RPM:
				phase = Phase.WARM
				_phase_time = 0.0
				status = "Warming up at idle"
			elif _phase_time > START_LIMIT:
				_fail("The engine did not start")
		Phase.WARM:
			throttle = 0.0
			clutch_pull = 0.0
			if not sim.running:
				_fail("The engine stalled at idle")
			elif _phase_time >= WARM_TIME:
				phase = Phase.CLUTCH
				_phase_time = 0.0
				clutch_pull = 1.0
				status = "Clutch in, selecting first"
		Phase.CLUTCH:
			# the drum moves only once the plates are apart, then the clutch is fed out against a closed throttle
			throttle = 0.0
			clutch_pull = 1.0
			if sim.clutch_engage < 0.12:
				_step_toward_first(sim.gear)
				if sim.gear.gear == 1:
					_gear = 1
					phase = Phase.TAKEUP
					_phase_time = 0.0
					status = "Taking up the clutch"
			elif _phase_time > SHIFT_LIMIT:
				_fail("The clutch did not open")
		Phase.TAKEUP:
			_feed_clutch(dt, sim, spec)
			if sim.clutch_engage > 0.99 and clutch_pull <= EngineSim.CLUTCH_BITE_START and sim.rpm < spec.idle_target_rpm * 2.6:
				_enter_pull(sim)
			elif not sim.running:
				_fail("The engine stalled as the clutch bit")
			elif _phase_time > TAKEUP_LIMIT:
				_fail("The clutch did not take up")
		Phase.PULL:
			throttle = 1.0
			clutch_pull = 0.0
		Phase.UPSHIFT:
			_upshift(dt, sim)


# Closed throttle, and the lever comes out only while the engine is holding near idle. A sag opens it back up.
func _feed_clutch(dt: float, sim: EngineSim, spec: EngineSpec) -> void:
	var low := spec.idle_target_rpm * 0.8
	var high := spec.idle_target_rpm * 2.4
	if sim.rpm < low and sim.clutch_engage > 0.25:
		throttle = 0.35
		clutch_pull = maxf(clutch_pull, EngineSim.CLUTCH_BITE_END)
	elif sim.rpm > high:
		throttle = 0.0
	else:
		throttle = 0.06
		clutch_pull = move_toward(clutch_pull, 0.0, _bite_rate * dt)


func _enter_pull(sim: EngineSim) -> void:
	phase = Phase.PULL
	_phase_time = 0.0
	_pull_deg = 0.0
	_window_t = 0.0
	_window_rpm = sim.rpm
	_last_cycle = sim.cycle_index
	throttle = 1.0
	clutch_pull = 0.0
	status = "Gear %d" % _gear


# Throttle shut, clutch open, one gear up, then the clutch home before the throttle opens again.
func _upshift(dt: float, sim: EngineSim) -> void:
	if _shift_style == "flat":
		_flat_shift(dt, sim)
		return
	throttle = 0.0
	if not _clicked:
		clutch_pull = 1.0
		if sim.clutch_engage < 0.12:
			_shift_up_one_gear(sim.gear)
			_gear = sim.gear.gear
			_clicked = true
			status = "Gear %d" % _gear
			# Quickshifter: trigger ignition/fuel cut for clutchless upshift
			if sim.ecu != null:
				sim.ecu.trigger_quickshifter(_spec)
		elif _phase_time > SHIFT_LIMIT:
			_fail("The clutch did not open for the shift")
	else:
		clutch_pull = move_toward(clutch_pull, 0.0, _bite_rate * 2.0 * dt)
		if sim.clutch_engage > 0.99 and clutch_pull <= EngineSim.CLUTCH_BITE_START:
			_clicked = false
			_enter_pull(sim)
		elif _phase_time > SHIFT_LIMIT:
			_fail("The clutch did not take up after the shift")


# A flat shift keeps a little throttle and only slips the clutch. If the box stays loaded, the rider tries once more.
func _flat_shift(dt: float, sim: EngineSim) -> void:
	if not _clicked:
		throttle = 0.25
		clutch_pull = 0.62
		if absf(sim.gearbox_load) < 8.0 or sim.clutch_engage < 0.5:
			_shift_up_one_gear(sim.gear)
			_gear = sim.gear.gear
			_clicked = true
			_misses = 0
			status = "Gear %d" % _gear
		elif _phase_time > 1.2:
			_misses += 1
			if _misses >= 2:
				_fail("Missed the shift into gear %d" % (_gear + 1))
			else:
				_phase_time = 0.0
				status = "Missed shift, trying again"
	else:
		clutch_pull = move_toward(clutch_pull, 0.0, _bite_rate * 3.0 * dt)
		throttle = move_toward(throttle, 1.0, dt / 0.2)
		if sim.clutch_engage > 0.99 and clutch_pull <= EngineSim.CLUTCH_BITE_START:
			_clicked = false
			_enter_pull(sim)
		elif _phase_time > SHIFT_LIMIT:
			_fail("The clutch did not take up after the flat shift")


# Takes a reading from a physics step with the clutch fully engaged and the throttle open. Then checks whether the gear is done.
func _observe(dt: float, sim: EngineSim) -> void:
	if phase != Phase.PULL:
		return
	if not sim.running:
		_fail("The engine stalled in gear %d" % _gear)
		return
	if sim.clutch_engage > 0.99 and throttle >= 0.99:
		_note_slip(sim)
	_pull_deg += sim.rpm * dt * 6.0
	# the cycle mean still belongs to the clutch take-up until the crank has turned once at full throttle
	var cycle_degrees := 360.0 if _spec.stroke_type == "two_stroke" else 720.0
	var qs_cut := sim.ecu != null and sim.ecu.quickshifter_cut_active()
	if _pull_deg >= cycle_degrees and clutch_pull <= 0.0 and sim.clutch_engage > 0.99 and throttle >= 0.99 and not sim.limiter_active and not qs_cut:
		_record(sim)
	_check_gear_end(sim)


func _check_gear_end(sim: EngineSim) -> void:
	# the redline counts only once the clutch has taken up: right after a shift the engine still spins at the old gear's rpm
	var last_gear := _gear >= _gear_count
	var at_redline := sim.clutch_engage > 0.99 and (sim.rpm >= _redline * (0.999 if last_gear else _shift_at) or sim.limiter_active)
	if _phase_time >= (TOP_GEAR_LIMIT if last_gear else GEAR_LIMIT) or at_redline:
		_end_reason = "limiter" if at_redline else "time_limit"
		_next_gear(sim)
	elif _phase_time - _window_t >= PLATEAU_WINDOW:
		# the bike has stopped gaining speed in this gear (top gear, at its top speed), so there is nothing more to read
		if _phase_time > _plateau_after and sim.rpm - _window_rpm < _plateau_rpm:
			_end_reason = "plateau"
			_next_gear(sim)
		else:
			_window_t = _phase_time
			_window_rpm = sim.rpm


# The fastest the bike went while this gear was driving. The clutch-open part of a shift is not counted.
func _note_speed(sim: EngineSim) -> void:
	var gear := sim.gear.gear
	if gear <= 0 or gear >= _max_speed.size() or sim.clutch_engage < 0.99:
		return
	if phase != Phase.PULL and not (phase == Phase.UPSHIFT and not _clicked):
		return
	if sim.speed > _max_speed[gear]:
		_max_speed[gear] = sim.speed
		_max_speed_rpm[gear] = sim.rpm


# Clutch slip while the clutch is fully engaged at full throttle: engine rpm minus the rpm the wheel is turning through the gear.
func _note_slip(sim: EngineSim) -> void:
	var gear := sim.gear.gear
	if gear <= 0 or gear >= _slip_n.size():
		return
	var ratio := _spec.primary_ratio * sim.gear.ratio() * _spec.final_drive
	var slip := slip_rpm(sim.rpm, sim.speed, ratio, EngineSim.tire_radius_m(_spec))
	if is_nan(slip):
		return
	_slip_n[gear] += 1.0
	_slip_sum[gear] += slip
	if slip > _slip_peak[gear]:
		_slip_peak[gear] = slip
		_slip_pct_peak[gear] = slip / maxf(sim.rpm, 1.0) * 100.0


# Engine rpm minus the engine rpm implied by the bike's road speed through the drive ratio. NAN when the geometry is unknown.
static func slip_rpm(engine_rpm: float, speed_ms: float, ratio: float, radius_m: float) -> float:
	if ratio <= 0.0 or radius_m <= 0.0:
		return NAN
	return engine_rpm - speed_ms / radius_m * ratio * 60.0 / TAU


func _record(sim: EngineSim) -> void:
	# The shaft torque of one step still carries the piston's inertia, which swings through every revolution. The cycle
	# mean is the torque a dyno reads. Steps before the first full cycle are skipped.
	if not sim.cycle_ready or sim.cycle_index == _last_cycle:
		return
	_last_cycle = sim.cycle_index
	var measured_rpm := sim.cycle_mean_rpm
	var b := clampi(int(measured_rpm / BIN_RPM), 0, _bins - 1)
	var i: int = _gear * _bins + b
	var measured := sim.cycle_brake_torque
	_sum_torque[i] += measured
	_sum_sq[i] += measured * measured
	_sum_rpm[i] += measured_rpm
	_sum_fuel[i] += sim.fuel_flow
	var lam := sim.o2_lambda()
	_sum_lambda[i] += lam if lam < 50.0 else 0.0
	_sum_egt[i] += sim.exhaust_temp_c()
	_sum_imap[i] += sim.intake.pressure
	_count[i] += 1.0


func _next_gear(_sim: EngineSim) -> void:
	_gear_end[_gear] = _end_reason
	if _gear >= _gear_count or (max_gears > 0 and _gear >= max_gears):
		_finish()
	else:
		phase = Phase.UPSHIFT
		_clicked = false
		_phase_time = 0.0
		clutch_pull = 1.0
		throttle = 0.0
		status = "Shifting to gear %d" % (_gear + 1)


func _restore_step() -> void:
	if _sim_ref != null and _saved_dt > 0.0:
		_sim_ref.physics_dt = _saved_dt
	_sim_ref = null


func _finish() -> void:
	_restore_step()
	phase = Phase.DONE
	throttle = 0.0
	clutch_held = false
	clutch_pull = 0.0
	status = "Dyno test complete"


func _fail(message: String) -> void:
	_restore_step()
	phase = Phase.DONE
	ok = false
	throttle = 0.0
	clutch_held = false
	clutch_pull = 0.0
	status = message


# One rider upshift. First to second passes the neutral detent in the same lever motion, because a full click does not stop there.
func _shift_up_one_gear(gear: Gearbox) -> void:
	shift_pedal_requested.emit(true)
	var before := gear.gear
	gear.shift_up()
	if before == 1 and gear.gear == 0:
		gear.shift_up()


# Clicks down toward first while the clutch is open. Second to first also passes neutral in one motion.
func _step_toward_first(gear: Gearbox) -> void:
	if gear.gear <= 1:
		if gear.gear == 0:
			shift_pedal_requested.emit(false)
			gear.shift_down()
		return
	var before := gear.gear
	shift_pedal_requested.emit(false)
	gear.shift_down()
	if before == 2 and gear.gear == 0:
		gear.shift_down()


# SAE J1349 spark-ignition correction: 99 kPa dry air and 25 °C. 1.0 means the run already was that day.
# CF = 1.18 (990 / p_dry_mbar) sqrt(T / 298) - 0.18, the form quoted in docs/engine_physics/11.
static func sae_j1349_factor(pressure_pa: float, temp_k: float, relative_humidity: float) -> float:
	var tc := temp_k - 273.15
	var saturation := 610.94 * exp(17.625 * tc / (tc + 243.04))
	var dry_mbar := maxf(pressure_pa - clampf(relative_humidity, 0.0, 1.0) * saturation, 1000.0) / 100.0
	return 1.18 * (990.0 / dry_mbar) * sqrt(temp_k / 298.0) - 0.18


static func to_json(r: Dictionary) -> String:
	return JSON.stringify(r, "\t")


static func to_csv(r: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append("rpm,torque_nm,hp,corrected_torque_nm,corrected_hp,bsfc_g_kwh,lambda,egt_c,intake_pa,torque_stdev,samples")
	for p in r.curve:
		lines.append("%.1f,%.3f,%.3f,%.3f,%.3f,%.1f,%.3f,%.1f,%.0f,%.3f,%.0f" % [
			p.rpm, p.torque, p.hp, p.corrected_torque, p.corrected_hp, p.bsfc_g_kwh, p.lambda, p.egt_c, p.intake_pa, p.torque_stdev, p.samples])
	lines.append("")
	lines.append("gear,torque_nm,torque_rpm,hp,hp_rpm,kmh,samples")
	for g in r.gears:
		lines.append("%d,%.3f,%.0f,%.3f,%.0f,%.1f,%.0f" % [g.gear, g.torque, g.torque_rpm, g.hp, g.hp_rpm, g.kmh, g.samples])
	lines.append("")
	lines.append("speed_kind,speed_end_reason,sample_basis")
	lines.append("%s,%s,%s" % [r.get("speed_kind", "road"), r.get("speed_end_reason", "unknown"), r.get("sample_basis", "unspecified")])
	return "\n".join(lines)


# Writes dyno_last.json and dyno_last.csv next to the given path's directory, using the path's file stem.
static func write_result(r: Dictionary, stem: String) -> void:
	var json_file := FileAccess.open(stem + ".json", FileAccess.WRITE)
	if json_file != null:
		json_file.store_string(to_json(r))
		json_file.close()
	var csv_file := FileAccess.open(stem + ".csv", FileAccess.WRITE)
	if csv_file != null:
		csv_file.store_string(to_csv(r))
		csv_file.close()


static func _zeros(size: int) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(size)
	for i in size:
		out[i] = 0.0
	return out
