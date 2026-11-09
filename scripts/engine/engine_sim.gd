class_name EngineSim
extends RefCounted

# Whole-bike physics with no scene nodes, so tests can run it directly.
# Each cylinder is a crank-angle gas model (Cylinder) at its firing angle, sharing one intake manifold.
# Crank speed comes from torque balance; the clutch joins the crank to the bike through
# the gear and final drive; the brake and road resistance slow the bike.

const FRICTION_BASE := 0.18 # N·m, rings, valve train and oil shear (pumping loss is in the cylinder model)
const MAIN_BEARING_FRICTION := 0.01 # N·m per main bearing, two bearings, estimate
const BALANCER_FRICTION := 0.005 # N·m, balancer shaft bearings and gear, estimate
const FRICTION_PER_CYLINDER := 0.1 # N·m per cylinder at a 57.3 mm bore (the CBR150R), piston rings and bores; estimate, see the friction note in the plan
const FRICTION_PER_RPM := 0.00012 # N·m per rpm, bearings and oil shear: about 1.2 N·m at 7,000 rpm (about 1 bar FMEP for a 150 cc single), estimate
const SUBSTEPS := 1 # each fixed physics step is taken once
var physics_dt := 1.0 / 1200.0 # s per physics step, set from the pause menu: Fast 1/1200, Normal 1/2400, Accurate 1/3600, Ultra 1/7200
const MAX_FRAME_TIME := 0.1 # s, the most real time one frame may add; a hitch must not make the sim run in fast-forward
const MAX_STEPS_PER_FRAME := 120 # one 60 Hz frame at the finest pause-menu rate (1/7200); a hitch past this is dropped
var _accumulator := 0.0 # real time not yet simulated, s
const STARTER_TORQUE := 20.0 # N·m per 150 cc at zero speed, fades to zero at CRANK_RPM; scaled from the CBR150R calibration, estimate
const CRANK_RPM := 900.0 # the starter's help fades to zero here, about the speed where the engine holds itself up
const FIRE_RPM := 400.0 # ignition catches the mixture above this speed
const STALL_RPM := 200.0 # below this the mixture no longer ignites
const LIMITER_CUT_TIME := 0.08 # s, spark held off per limiter hit, from engine-sim's ignition module
const DRAG_CDA := 0.40 # m², drag coefficient times frontal area: a naked sport bike with rider, Cd about 0.65 on about 0.6 m², estimate
const AIR_DENSITY := 1.2 # kg/m³
const ROLLING_COEFF := 0.015
const GRAVITY := 9.81
const CLUTCH_STIFFNESS := 200.0 # N·m per rad/s, how firmly the clutch grips; high so a locked clutch holds speed × ratio (about 0.07 rad/s slip at cruise)
# Clutch pack: torque = friction coefficient × spring force × mean radius × friction faces.
# Estimates for a 150 cc single: 5 friction plates, 10 faces, 600 N total spring force.
const CLUTCH_MU := 0.12 # friction coefficient, wet clutch, estimate
const CLUTCH_SPRING_N := 600.0 # N, all springs together, fully engaged, estimate
const CLUTCH_MEAN_R := 0.035 # m, mean radius of the friction faces, estimate
const CLUTCH_FACES := 10.0 # friction faces (5 plates, two faces each)
const CLUTCH_NM_PER_CC := 0.1 # N·m of clutch capacity per cc, so big engines don't slip; estimate, 150 cc keeps the 25 N·m default
const CLUTCH_ENGAGE_TIME := 0.6 # s, the lever comes back in about half a second: slow enough to bite gently, quick enough for gear changes
const CLUTCH_RELEASE_TIME := 0.05 # s, pulling the clutch in is fast
const CLUTCH_LEVER_TIME := 0.03 # s, the plates follow the lever with only this much lag
const CLUTCH_BITE_START := 0.5 # lever pull where the plates start to slip, estimate: the friction zone begins here
const CLUTCH_BITE_END := 0.9 # lever pull where the plates are fully apart, estimate: the friction zone ends here
const DRIVE_EFFICIENCY := 0.93 # gearbox mesh (6 gears, ~1.5% each), primary drive and chain (~3%) together, estimate
const BRAKE_FORCE := 1800.0 # N, both brakes together, estimate (about 0.85 g on 215 kg)
const BRAKE_APPLY_TIME := 0.2 # s, brake lever pulls on over this time
# Slipper clutch: reduces clutch capacity during engine braking (negative gearbox load) to prevent rear wheel hop
const SLIPPER_CLUTCH_RAMP := 0.5 # fraction of capacity retained during engine braking (0.5 = 50% capacity on overrun)
# Fuel evaporating in the intake cools the air drawn in. Only part of the fuel evaporates before the valve shuts (estimate).
const CHARGE_EVAP_FRACTION := 0.1 # calibrated so E85 gains about 5% wide-open torque over petrol: its 3% more energy per kg of air plus the cooler charge, the top of the published range
# Knock: the stock ignition map is safe on any fuel. Advancing it by more than the limit knocks: higher octane and lower compression allow more (estimates).
const KNOCK_BASE_DEG := 4.0
const KNOCK_PER_OCTANE_DEG := 0.4
const KNOCK_PER_CR_DEG := 0.5
const KNOCK_TORQUE_LOSS := 0.3 # share of the gas torque lost when the advance is 5 degrees past the limit (estimate)

var rpm := 0.0 # engine speed
var omega := 0.0 # crank speed, rad/s
var speed := 0.0 # bike speed, m/s
var running := false # the mixture is lit
var limiter_active := false # the rev limiter has the spark cut
var clutch_engage := 1.0 # 0 = clutch open, 1 = fully engaged
var clutch_pull := 0.0 # 0 to 1 from the clutch lever: 1 = pulled in, 0 = at rest (engaged unless Shift is held)
var brake := 0.0 # 0 = released, 1 = fully applied
# Dyno cell only: eddy-current brake force at the wheel, N, and the drum's equivalent mass, kg (0 = the bike's own settings)
var cell_load_n := 0.0
var cell_mass_kg := 0.0
var fuel_flow := 0.0 # g/s, averaged over the last frame and smoothed over about two engine cycles
var torque := 0.0 # N·m at the crank, shaft torque averaged over the last step
var gear := Gearbox.new()
var intake := EngineAir.new()
var fuel := FuelTank.new()
var cylinders: Array[RefCounted] = [] # Cylinder (four-stroke) or TwoStrokeCylinder: they share the fields the sim reads
var exhaust: ExhaustGas # one column for every header; null until the cylinders are built
var _cyl_key := ""
var _limiter_time := 0.0
var ecu := ECU.new()
var _ecu_binary_path := ""
var _ecu_limiter_rpm := 0.0
var _ecu_calibration_status := "No ECU calibration loaded"
var _ecu_calibration: Dictionary = {}
# Runtime-ready N04 values. The source maps remain in _ecu_calibration for
# diagnostics, while the physics loop reads these pre-blended tables.
var _ecu_rpm_axis: Array = []
var _ecu_tps_axis: Array = []
var _ecu_map_axis: Array = []
var _ecu_ignition_map: Array = []
var _ecu_fuel_lambda_map: Array = []
var _ecu_torque_caps: Array = []
var _ecu_tbw_maps: Array = []
var _ecu_speed_limit_kmh := 0.0
var _gas_torque := 0.0 # N·m, the gas torque from the last physics step, used in the next crank kick
var _rev_deg := 0.0 # crank degrees gathered toward one four-stroke cycle
var _rev_tq := 0.0 # shaft-torque × degrees over that gather
var _rev_time := 0.0
var cycle_index := 0 # increases only when a new complete cycle is available
var cycle_mean_rpm := 0.0
var cycle_brake_torque := 0.0 # N·m, mean shaft torque over the last closed cycle
var cycle_ready := false # true once one full cycle of shaft torque has been averaged
var oil_c := 100.0 # °C, warms toward the spec's operating temperature; cold oil raises friction
var coolant_c := 90.0 # °C, a hot coolant trims the knock margin
var _fluids_set := false
var _prev_power_mode := "F" # track power mode changes for ECU sync
var audio_enabled := true # record intake and exhaust samples for the sound
# Transient fuel: a quick throttle opening richens the mixture, as the accelerator pump does on a carburettor and the
# fuel map does on injection, and the richness fades back to the steady mixture.
const ACCEL_ENRICH_PER_UNIT := 0.12 # richness added per unit of throttle opening: a full snap is about 12 percent
const ACCEL_ENRICH_MAX := 0.1
const ACCEL_ENRICH_TIME := 0.3 # s, how fast the extra fuel fades
var _throttle_prev := 0.0
var _accel_enrich := 0.0
var exhaust_solver := false # the 1D pipe solver for the four-stroke live path. Off: its idle drops to ~45 kPa in the pipes, so it is for offline renders. The two-stroke always runs it (uses_pipe_sound).
var _intake_flow := PackedFloat32Array()
var _intake_audio_left := 0.0
var _blowdown := PackedFloat32Array()
var _blowdown_left := 0.0
var _audio_layout: ExhaustLayout
var _runner_delays := PackedInt32Array()
var _runner_gain := PackedFloat32Array()
var _runner_history := PackedFloat32Array()
var _runner_stride := 0
var _runner_head := 0
var _runner_dt := 0.0
var _runner_count := 0
var _clutch_slow_engage := false # true after a Shift pull-in, until the plates are back: then they come back slowly
var knock_count := 0 # knock events since the engine was made: each time the advance goes past the limit
var _knocking := false
var knock_excess := 0.0 # degrees the advance is past the knock limit now: 0 when the engine is not knocking
var backfire_count := 0 # backfires since the engine was made, for the sound to hear each one once
var last_backfire_j := 0.0 # J released by the latest backfire, for its loudness
var gearbox_load := 0.0 # N·m, torque transmitted through clutch to gearbox (positive = driving, negative = engine braking)


# Advances the bike by delta seconds of real time, in fixed physics steps. The physics is the same at any frame rate: a
# slow frame runs more steps, not bigger ones.
func step(delta: float, spec: EngineSpec, throttle: float, ignition: bool, starter_held: bool,
		clutch_held: bool, brake_held: bool, lambda: float) -> void:
	if delta <= 0.0:
		return
	_sync_ecu_calibration(spec)
	_build_cylinders(spec)
	if omega == 0.0 and rpm == 0.0 and speed == 0.0 and not running and not starter_held and absf(_gas_torque) < 0.0001 and absf(intake.pressure - Cylinder.P0) <= Cylinder.P0 * 0.01:
		intake.boost_ratio = 1.0
		intake.compressor_load = 0.0
		_update_controls(minf(delta, MAX_FRAME_TIME), clutch_held, brake_held)
		_warm_fluids(minf(delta, MAX_FRAME_TIME), spec)
		gear.gear_ratios = spec.gear_ratios
		_update_limiter(minf(delta, MAX_FRAME_TIME), effective_limiter_rpm(spec))
		limiter_active = intake.limiter_cut
		gearbox_load = 0.0
		_knocking = false
		_accumulator = 0.0
		torque = 0.0
		fuel_flow = 0.0
		return
	_accumulator = minf(_accumulator + delta, MAX_FRAME_TIME)
	var fuel_start := fuel.mass_kg
	var n := 0
	while _accumulator >= physics_dt and n < MAX_STEPS_PER_FRAME:
		_advance(physics_dt, spec, throttle, ignition, starter_held, clutch_held, brake_held, lambda)
		_accumulator -= physics_dt
		n += 1
	if _accumulator >= physics_dt:
		_accumulator = 0.0 # still behind after the step limit: drop the backlog rather than fast-forward
	# Fuel is injected once per engine cycle, so one physics step sees either all of it or none. The flow is the fuel used over
	# the whole frame, smoothed over about two engine cycles, so the sound and the readouts get a steady value.
	if n > 0:
		var instant := (fuel_start - fuel.mass_kg) * 1000.0 / (n * physics_dt)
		var tau := clampf(240.0 / maxf(rpm, 100.0), 0.05, 0.5)
		fuel_flow += (instant - fuel_flow) * (1.0 - exp(-n * physics_dt / tau))


func _update_controls(delta: float, clutch_held: bool, brake_held: bool) -> void:
	# the lever sets how far apart the plates are: engaged up to the bite point, slipping through the friction zone, open past it.
	# The Shift key pulls the clutch fully in, and when it lets go the plates come back slowly
	var grip_target := 0.0 if clutch_held else clutch_grip(clutch_pull)
	if clutch_held:
		_clutch_slow_engage = true
	var time := CLUTCH_LEVER_TIME
	if grip_target < clutch_engage:
		time = CLUTCH_RELEASE_TIME
	elif _clutch_slow_engage:
		time = CLUTCH_ENGAGE_TIME
	clutch_engage = move_toward(clutch_engage, grip_target, delta / time)
	if clutch_engage >= grip_target and not clutch_held:
		_clutch_slow_engage = false
	brake = move_toward(brake, 1.0 if brake_held else 0.0, delta / BRAKE_APPLY_TIME)


# One fixed physics step of delta seconds.
# Lambda multiplier for this physics step: below 1 while the throttle is opening, back to 1 once it has settled.
func _transient_lambda_mult(throttle: float, delta: float) -> float:
	# the pump delivers fuel in proportion to how far the throttle moved, however fast it moved
	var opened := throttle - _throttle_prev
	_throttle_prev = throttle
	if opened > 0.0:
		_accel_enrich = minf(_accel_enrich + opened * ACCEL_ENRICH_PER_UNIT, ACCEL_ENRICH_MAX)
	_accel_enrich *= exp(-delta / ACCEL_ENRICH_TIME)
	return 1.0 - _accel_enrich


func _advance(delta: float, spec: EngineSpec, throttle: float, ignition: bool, starter_held: bool,
		clutch_held: bool, brake_held: bool, lambda: float) -> void:
	var is_two_stroke := spec.stroke_type == "two_stroke"
	if is_two_stroke:
		_advance_two_stroke(delta, spec, throttle, ignition, starter_held, clutch_held, brake_held, lambda)
		return
	
	_update_controls(delta, clutch_held, brake_held)

	if not ignition or rpm < STALL_RPM:
		running = false
	elif rpm >= FIRE_RPM:
		running = true

	var inertia := spec.rotating_inertia()
	gear.gear_ratios = spec.gear_ratios
	var ratio := spec.primary_ratio * gear.ratio() * spec.final_drive
	var radius := tire_radius_m(spec)
	var h := delta / SUBSTEPS
	var torque_sum := 0.0
	# knock: the rider's advance past what the fuel and compression allow, which costs torque and counts as a knock
	_warm_fluids(delta, spec)
	var knock_limit := knock_limit_deg(fuel.octane, spec.compression_ratio) - coolant_knock_penalty_deg(coolant_c)
	knock_excess = maxf(spec.ignition_offset_deg - knock_limit, 0.0)
	if running and knock_excess > 0.0 and not _knocking:
		knock_count += 1
	_knocking = running and knock_excess > 0.0
	var knock_loss := clampf(knock_excess / 5.0, 0.0, 1.0) * KNOCK_TORQUE_LOSS
	# the fuel evaporating in the intake cools the air drawn in, so E85 and petrol breathe differently
	# The N04 flash proves its rev limiter, but its fuel, torque, throttle and
	# ignition tables have no verified selector or engineering-unit schema yet.
	# Do not turn raw bytes into an unphysical power correction.  The cylinder
	# model remains driven by the rider command and its physical mixture target.
	var calibrated_throttle := throttle
	var target_lambda := EngineAir.get_target_lambda(spec, calibrated_throttle, rpm) * lambda * _transient_lambda_mult(throttle, delta)
	var intake_temp := EngineAir.T0 - (charge_cooling_k(fuel.latent, fuel.afr, target_lambda) if running else 0.0)
	for _i in SUBSTEPS:
		_update_limiter(h, effective_limiter_rpm(spec))
		# piston rings and bores: each cylinder's ring face grows with its bore. Scaled so a 57.3 mm bore gives FRICTION_PER_CYLINDER.
		var friction := FRICTION_BASE + 2.0 * MAIN_BEARING_FRICTION + BALANCER_FRICTION + FRICTION_PER_RPM * rpm
		friction += spec.cylinders * FRICTION_PER_CYLINDER * (spec.bore_mm / 57.3)
		# constant crankshaft friction: full strength once the crank turns, fading to nothing as it stops
		friction += spec.crank_friction_nm * minf(rpm / 50.0, 1.0)
		friction *= oil_friction_scale(oil_c, spec.oil_operating_c)
		# kick first, as engine-sim's NSV solver does: the crank speed moves with the gas torque from the last step
		var net := _gas_torque
		if starter_held: # the starter keeps turning the engine while it is held, even after the engine fires
			var starter := spec.starter_torque_nm if spec.starter_torque_nm > 0.0 else STARTER_TORQUE * spec.displacement_cc / 150.0
			net += starter * clampf(1.0 - rpm / CRANK_RPM, 0.0, 1.0)
		net -= friction

		_advance_driveline(h, spec, net, inertia, ratio, radius)

		# drift next: the cylinders and the intake see the crank step in smaller sub-steps (the intake fills and empties
		# fast, so one coarse step overshoots), and the average gas torque is used in the next kick
		# the ECU trims the spark advance at idle to hold the idle speed
		ecu.target_rpm = spec.idle_target_rpm
		# Sync ECU power mode if changed
		if spec.power_mode != _prev_power_mode:
			ecu.set_power_mode(spec.power_mode)
			_prev_power_mode = spec.power_mode
		var base_advance := EngineAir.spark_advance_deg(rpm)
		var throttle_override := ecu.update(h, rpm, throttle, running, spec, speed, clutch_pull, gear.gear)
		calibrated_throttle = throttle_override if throttle_override >= 0.0 else throttle
		var ecu_trim := ecu.trim
		var ign := 720.0 - (base_advance + spec.ignition_offset_deg + ecu_trim)
		var gas := 0.0
		var step_deg := 0.0
		var sub := maxi(1, ceili(h / Cylinder.MAX_FLOW_DT))
		var sub_h := h / sub
		# At high RPM, four cylinders at 10° cost enough CPU to stall live input.
		# Offline exhaust renders retain the 10° integration path for comparison output.
		var live_fast_step := not exhaust_solver and cylinders.size() >= 4 and rpm >= 8000.0
		# Quickshifter: cut ignition and fuel during upshift
		var qs_cut := ecu.quickshifter_cut_active()
		for _j in sub:
			var dphi := omega * sub_h * 180.0 / PI
			step_deg += absf(dphi)
			var drawn := 0.0
			for ci in cylinders.size():
				var c: Cylinder = cylinders[ci]
				c.flow_step_deg = Cylinder.LIVE_HIGH_RPM_STEP_DEG if live_fast_step else Cylinder.STEP_DEG
				# the pipe end from the previous gas step is what this valve blows into. Live play uses the open air.
				var p_ex := Cylinder.P0
				var t_ex := Cylinder.T0
				if exhaust_solver and exhaust != null:
					p_ex = exhaust.port_pressure(ci)
					t_ex = exhaust.port_temperature(ci)
				# limiter cuts both spark AND fuel to prevent unburnt mixture in exhaust
				var cut := intake.limiter_cut or ecu.overrun() or qs_cut
				# Power mode lambda multiplier
				var mode_lambda := target_lambda * ecu.get_power_mode_lambda_mult()
				var res := c.advance(dphi, sub_h, intake.pressure, intake_temp, ign, running, fuel, mode_lambda, running and not cut, cut, p_ex, t_ex)
				gas += res.x / sub
				drawn += res.y
				if exhaust_solver and exhaust != null:
					exhaust.apply_valve(ci, c.exhaust_mdot, c.exhaust_power)
				if c.backfire_j > 0.0:
					backfire_count += 1
					last_backfire_j = c.backfire_j
					if exhaust_solver and exhaust != null:
						exhaust.add_energy(ci, c.backfire_j * 0.05)
					c.backfire_j = 0.0
			if exhaust_solver and exhaust != null:
				exhaust.record_audio = audio_enabled
				exhaust.advance(sub_h)
			elif audio_enabled:
				var blow_mdot := 0.0
				var blow_t := 0.0
				for c in cylinders:
					blow_t += c.exhaust_temp
				if _audio_layout != null and (_runner_dt != sub_h or _runner_count != cylinders.size()):
					_configure_runner_delays(sub_h, cylinders.size())
				if _runner_delays.size() == cylinders.size():
					blow_mdot = _route_exhaust_flow()
				else:
					for c in cylinders:
						blow_mdot += c.exhaust_mdot
				var blow_rho := Cylinder.P0 / (Cylinder.R * maxf(blow_t / maxf(cylinders.size(), 1), 250.0))
				# Normalize by cylinder count so audio level is consistent regardless of cylinder count
				_emit_blowdown((blow_mdot / blow_rho) / spec.cylinders, sub_h)
				if audio_enabled:
					var intake_mdot := 0.0
					for c in cylinders:
						intake_mdot += c.runner_q
					var rho := maxf(intake.pressure / (Cylinder.R * maxf(intake_temp, 200.0)), 0.2)
					# Normalize by cylinder count
					_emit_intake((intake_mdot / rho) / spec.cylinders, sub_h)
			intake.bypass_area = EngineAir.BYPASS_AREA * spec.displacement_cc / 149.2 * ecu.air_factor() # idle air scales with displacement; the ECU's idle valve sets the rest
			intake.manifold_update(sub_h, calibrated_throttle, drawn / sub_h, spec, rpm, running, speed if cell_mass_kg <= 0.0 else 0.0)
		gas *= 1.0 - knock_loss
		_gas_torque = gas
		_accumulate_cycle(gas - friction, step_deg, h, 720.0)
		torque_sum += gas - friction # shaft torque, what the crank delivers
		rpm = omega * 60.0 / TAU
	limiter_active = intake.limiter_cut
	torque = torque_sum / SUBSTEPS


# Two-stroke physics step: crankcase compression + cylinder combustion + expansion chamber
func _advance_two_stroke(delta: float, spec: EngineSpec, throttle: float, ignition: bool, starter_held: bool,
		clutch_held: bool, brake_held: bool, lambda: float) -> void:
	
	_update_controls(delta, clutch_held, brake_held)
	
	if not ignition or rpm < STALL_RPM:
		running = false
	elif rpm >= FIRE_RPM:
		running = true
	
	var inertia := spec.rotating_inertia()
	gear.gear_ratios = spec.gear_ratios
	var ratio := spec.primary_ratio * gear.ratio() * spec.final_drive
	var radius := tire_radius_m(spec)
	var h := delta / SUBSTEPS
	var torque_sum := 0.0
	
	_warm_fluids(delta, spec)
	var knock_limit := knock_limit_deg(fuel.octane, spec.compression_ratio) - coolant_knock_penalty_deg(coolant_c)
	knock_excess = maxf(spec.ignition_offset_deg - knock_limit, 0.0)
	if running and knock_excess > 0.0 and not _knocking:
		knock_count += 1
	_knocking = running and knock_excess > 0.0
	var knock_loss := clampf(knock_excess / 5.0, 0.0, 1.0) * KNOCK_TORQUE_LOSS
	
	# Two-stroke: target lambda from spec map
	var calibrated_throttle := throttle
	var target_lambda := EngineAir.get_target_lambda(spec, calibrated_throttle, rpm) * lambda * _transient_lambda_mult(throttle, delta)
	var intake_temp := EngineAir.T0 - (charge_cooling_k(fuel.latent, fuel.afr, target_lambda) if running else 0.0)
	
	# Friction: 2-stroke has less friction (no valve train) but more ring friction
	var friction := FRICTION_BASE * 0.7 + 2.0 * MAIN_BEARING_FRICTION + BALANCER_FRICTION + FRICTION_PER_RPM * rpm
	friction += spec.cylinders * FRICTION_PER_CYLINDER * (spec.bore_mm / 57.3) * 1.2
	friction += spec.crank_friction_nm * minf(rpm / 50.0, 1.0)
	friction *= oil_friction_scale(oil_c, spec.oil_operating_c)
	
	# Ignition timing for 2-stroke: the same ECU idle loop as the four-stroke, so the engine holds its idle at a closed throttle
	var base_advance := EngineAir.spark_advance_deg(rpm)
	ecu.target_rpm = spec.idle_target_rpm
	ecu.update(h, rpm, throttle, running, spec, speed, clutch_pull, gear.gear)
	var ign := 360.0 - (base_advance + spec.ignition_offset_deg + ecu.trim)
	
	for _i in SUBSTEPS:
		_update_limiter(h, effective_limiter_rpm(spec))
		
		var net := _gas_torque
		if starter_held:
			var starter := spec.starter_torque_nm if spec.starter_torque_nm > 0.0 else STARTER_TORQUE * spec.displacement_cc / 150.0
			net += starter * clampf(1.0 - rpm / CRANK_RPM, 0.0, 1.0)
		net -= friction
		
		_advance_driveline(h, spec, net, inertia, ratio, radius)
		
		# Cylinder advance (360° cycle for 2-stroke)
		# Each cylinder fires every 360°
		var gas := 0.0
		var step_deg := 0.0
		var sub := maxi(1, ceili(h / TwoStrokeCylinder.STEP_DEG))
		var sub_h := h / sub
		
		var drawn: float = 0.0
		for _j in sub:
			var dphi := omega * sub_h * 180.0 / PI
			step_deg += absf(dphi)
			for ci in cylinders.size():
				var c: RefCounted = cylinders[ci]
				# 2-stroke cylinder advance
				# the chamber (or pipe) this cylinder breathes into: its own pressure and temperature, as the four-stroke gets
				var ex_p := Cylinder.P0
				var ex_t := Cylinder.T0
				if exhaust != null:
					ex_p = exhaust.port_pressure(ci)
					ex_t = exhaust.port_temperature(ci)
				var res: Vector2 = c.advance(dphi, sub_h, intake.pressure, intake_temp, ign, running, fuel, target_lambda, running and not intake.limiter_cut, intake.limiter_cut, ex_p, ex_t)
				gas += res.x / sub
				drawn += res.y
				
				if exhaust != null:
					exhaust.apply_valve(ci, c.exhaust_mdot, c.exhaust_power)
			# the chambers and pipes move on one step, with every cylinder's flow in
			if exhaust != null:
				exhaust.record_audio = audio_enabled
				exhaust.advance(sub_h)
		
		# Intake manifold update with 2-stroke crankcase pumping
		intake.bypass_area = EngineAir.BYPASS_AREA * spec.displacement_cc / 149.2 * ecu.air_factor() # idle air, as the four-stroke
		intake.manifold_update(h, throttle, drawn / h, spec, rpm, running, speed if cell_mass_kg <= 0.0 else 0.0)
		
		gas *= 1.0 - knock_loss
		_gas_torque = gas
		_accumulate_cycle(gas - friction, step_deg, h, 360.0)
		torque_sum += gas - friction
	
	rpm = omega * 60.0 / TAU
	limiter_active = intake.limiter_cut
	torque = torque_sum / SUBSTEPS


# Volume flow into the intake valves since the last take, one sample per audio frame. The caller owns the array.
func take_intake_flow() -> PackedFloat32Array:
	var out := _intake_flow
	_intake_flow = PackedFloat32Array()
	return out


# Volume flow out of the exhaust valves since the last take. Used for the live sound while the pipe solver is off.
func take_blowdown() -> PackedFloat32Array:
	var out := _blowdown
	_blowdown = PackedFloat32Array()
	return out


# Rebuild audio-only propagation paths without changing cylinder or exhaust physics.
func set_audio_layout(layout: ExhaustLayout, count: int) -> void:
	_audio_layout = layout
	# the solver runs the same pipes the drawing shows, so the sound, the pressures and the picture agree
	if exhaust != null and layout != null:
		exhaust.build(layout)
	_blowdown = PackedFloat32Array()
	_blowdown_left = 0.0
	var dt := physics_dt / maxi(1, ceili(physics_dt / Cylinder.MAX_FLOW_DT))
	_configure_runner_delays(dt, count)


func _configure_runner_delays(dt: float, count: int) -> void:
	_runner_delays = PackedInt32Array()
	_runner_gain = PackedFloat32Array()
	_runner_history = PackedFloat32Array()
	_runner_head = 0
	_runner_dt = dt
	_runner_count = count
	if _audio_layout == null or count <= 0 or dt <= 0.0:
		return
	var pipes := _audio_layout.pipes
	var parents := PackedInt32Array()
	parents.resize(pipes.size())
	parents.fill(-1)
	for i in pipes.size():
		for feeder in pipes[i].feeders:
			if feeder < 0 or feeder >= i or parents[feeder] != -1:
				return
			parents[feeder] = i
	var primaries := PackedInt32Array()
	primaries.resize(count)
	primaries.fill(-1)
	for i in pipes.size():
		var pipe: ExhaustLayout.Pipe = pipes[i]
		if pipe.kind == "primary" and pipe.cyl >= 0 and pipe.cyl < count:
			if primaries[pipe.cyl] != -1:
				return
			primaries[pipe.cyl] = i
	var delays := PackedInt32Array()
	var gains := PackedFloat32Array()
	var longest := 0
	for ci in count:
		var index := primaries[ci]
		if index < 0:
			return
		var length := 0.0
		var loss := 0.0
		var end_kind := ""
		while index >= 0:
			var pipe: ExhaustLayout.Pipe = pipes[index]
			end_kind = pipe.kind
			var segment := pipe.length_m()
			length += segment
			if pipe.kind != "muffler" and pipe.kind != "catalyst":
				loss += segment * maxf(pipe.loss, 0.0)
			index = parents[index]
		if end_kind != "tail" or length <= 0.0 or length > 20.0:
			return
		var delay := roundi(length / (500.0 * dt)) # representative speed of sound in hot exhaust, m/s
		delays.append(delay)
		gains.append(exp(-0.2 * loss))
		longest = maxi(longest, delay)
	_runner_stride = longest + 1
	_runner_history.resize(count * _runner_stride)
	_runner_delays = delays
	_runner_gain = gains


func _route_exhaust_flow() -> float:
	var flow := 0.0
	for ci in cylinders.size():
		var base := ci * _runner_stride
		_runner_history[base + _runner_head] = cylinders[ci].exhaust_mdot
		var read := _runner_head - _runner_delays[ci]
		if read < 0:
			read += _runner_stride
		flow += _runner_history[base + read] * _runner_gain[ci]
	_runner_head += 1
	if _runner_head == _runner_stride:
		_runner_head = 0
	return flow


# Mean pressure the exhaust valves blow into, Pa. Atmosphere when there is no pipe.
# True when the sound and back pressure come from the pipes: the two-stroke always does, the four-stroke only when the solver is on.
func uses_pipe_sound() -> bool:
	if exhaust == null or cylinders.is_empty():
		return false
	return exhaust_solver or cylinders[0] is TwoStrokeCylinder


func backpressure_pa() -> float:
	if not uses_pipe_sound():
		return Cylinder.P0
	var sum := 0.0
	for i in cylinders.size():
		sum += exhaust.port_pressure(i)
	return sum / cylinders.size()


func _emit_intake(volume_flow: float, dt: float) -> void:
	_intake_audio_left += dt
	var count := int(_intake_audio_left * ExhaustGas.AUDIO_RATE)
	if count <= 0:
		return
	count = mini(count, 4096)
	_intake_audio_left -= float(count) / ExhaustGas.AUDIO_RATE
	for i in count:
		_intake_flow.append(volume_flow)


func _emit_blowdown(volume_flow: float, dt: float) -> void:
	_blowdown_left += dt
	var count := int(_blowdown_left * ExhaustGas.AUDIO_RATE)
	if count <= 0:
		return
	count = mini(count, 4096)
	_blowdown_left -= float(count) / ExhaustGas.AUDIO_RATE
	for i in count:
		_blowdown.append(volume_flow)


# The CBR250RR preset supplies its N04 flash through EngineSpec.  Only values
# whose layout and meaning are verified are allowed to affect live physics.
func _sync_ecu_calibration(spec: EngineSpec) -> void:
	var path := spec.ecu_binary
	if path == _ecu_binary_path:
		return
	_ecu_binary_path = path
	_ecu_limiter_rpm = 0.0
	_ecu_calibration = {}
	_clear_ecu_calibration_cache()
	_ecu_calibration_status = "No ECU calibration loaded" if path.is_empty() else "ECU calibration unavailable"
	if path.is_empty():
		return
	var parser := ECUBinaryParser.new()
	if not parser.load_binary(path):
		_ecu_calibration_status = parser.get_error()
		return
	var data := parser.parse_all()
	if data.is_empty():
		_ecu_calibration_status = "ECU calibration contains no decoded tables"
		return
	var limiter: Array = data.get("limiter_1", [])
	if limiter.is_empty() or int(limiter[0]) <= 0:
		_ecu_calibration_status = "ECU calibration has no verified primary limiter"
		return
	_ecu_limiter_rpm = float(limiter[0])
	_ecu_calibration = data
	_prepare_ecu_calibration_cache()
	_ecu_calibration_status = parser.get_layout() + ": verified limiter %.0f RPM (raw maps diagnostic only)" % _ecu_limiter_rpm


# A user-selected lower redline remains a valid safety limit.  The verified
# ECU value prevents the CBR250RR from revving past the flash's fuel/spark cut.
func effective_limiter_rpm(spec: EngineSpec) -> float:
	if _ecu_limiter_rpm > 0.0:
		return minf(spec.redline_rpm, _ecu_limiter_rpm)
	return spec.redline_rpm


func ecu_calibration_status() -> String:
	return _ecu_calibration_status


func _clear_ecu_calibration_cache() -> void:
	_ecu_rpm_axis = []
	_ecu_tps_axis = []
	_ecu_map_axis = []
	_ecu_ignition_map = []
	_ecu_fuel_lambda_map = []
	_ecu_torque_caps = []
	_ecu_tbw_maps = []
	_ecu_speed_limit_kmh = 0.0


# The source dump has 10 ignition maps and several raw limiter tables. Their
# values do not change while a binary is selected, so blend/normalize once at
# load time instead of re-scanning them in every 1/1200-second physics step.
func _prepare_ecu_calibration_cache() -> void:
	_ecu_rpm_axis = _ecu_calibration.get("rpm_axis", [])
	_ecu_tps_axis = _ecu_calibration.get("tps_axis", [])
	_ecu_map_axis = _ecu_calibration.get("map_axis", [])
	if _ecu_rpm_axis.is_empty() or _ecu_tps_axis.is_empty() or _ecu_map_axis.is_empty():
		return
	for gear_number in range(1, 7):
		var raw_tbw: Array = _ecu_calibration.get("tbw_sport_" + str(gear_number), [])
		var normalized_tbw: Array = []
		if not raw_tbw.is_empty():
			var full := maxf(float(raw_tbw[raw_tbw.size() - 1]), 0.001)
			for value in raw_tbw:
				normalized_tbw.append(clampf(float(value) / full, 0.0, 1.0))
		_ecu_tbw_maps.append(normalized_tbw)
	var raw_torque: Array = _ecu_calibration.get("torque_limiter_gear", [])
	for gear_index in range(6):
		var cap: Array = []
		var maximum := 0.0
		for row in raw_torque:
			if row is Array and row.size() > gear_index:
				var value := float(row[gear_index])
				cap.append(value)
				maximum = maxf(maximum, value)
		for index in cap.size():
			cap[index] = cap[index] / maxf(maximum, 0.001)
		_ecu_torque_caps.append(cap)
	var source_fuel: Array = _ecu_calibration.get("fuel_5_tps_rpm", [])
	if not source_fuel.is_empty():
		var full_fuel_row: Array = source_fuel[source_fuel.size() - 1]
		for row in source_fuel:
			var lambda_row: Array = []
			for column in row.size():
				var pulse := float(row[column])
				var full_pulse := float(full_fuel_row[column])
				lambda_row.append(clampf(full_pulse / maxf(pulse, 0.001), 0.85, 1.20))
			_ecu_fuel_lambda_map.append(lambda_row)
	var map_rows := _ecu_map_axis.size()
	var map_columns := _ecu_rpm_axis.size()
	for row_index in map_rows:
		var average_row: Array = []
		for column_index in map_columns:
			var sum := 0.0
			var count := 0
			for map_id in range(1, 6):
				for cylinder in range(1, 3):
					var map: Array = _ecu_calibration.get("ign_%d_cyl%d" % [map_id, cylinder], [])
					if map.size() > row_index and map[row_index].size() > column_index:
						sum += float(map[row_index][column_index])
						count += 1
			average_row.append(sum / count if count > 0 else 0.0)
		_ecu_ignition_map.append(average_row)
	for key in ["speed_limiter_1", "speed_limiter_2"]:
		for value in _ecu_calibration.get(key, []):
			if float(value) > 0.0:
				_ecu_speed_limit_kmh = float(value) if _ecu_speed_limit_kmh <= 0.0 else minf(_ecu_speed_limit_kmh, float(value))


# The verified K64 maps use a 0..661 throttle sensor and a roughly 0..594
# intake-pressure sensor. The tables' selecting conditions are not documented,
# so the five available maps are blended instead of claiming a false factory
# map-switch rule. Every output is clamped to a safe physical range.
func ecu_throttle(throttle: float) -> float:
	if _ecu_tbw_maps.is_empty() or gear.gear < 1 or gear.gear > 6:
		return clampf(throttle, 0.0, 1.0)
	var table: Array = _ecu_tbw_maps[gear.gear - 1]
	if table.is_empty():
		return clampf(throttle, 0.0, 1.0)
	return _interpolate_index(table, throttle)


func ecu_torque_throttle_cap() -> float:
	if _ecu_torque_caps.is_empty() or gear.gear < 1 or gear.gear > 6:
		return 1.0
	var values: Array = _ecu_torque_caps[gear.gear - 1]
	if values.is_empty() or values.size() != _ecu_rpm_axis.size():
		return 1.0
	return clampf(_interpolate_axis(values, _ecu_rpm_axis, rpm), 0.0, 1.0)


func ecu_fuel_lambda_multiplier(throttle: float) -> float:
	if _ecu_fuel_lambda_map.is_empty() or _ecu_tps_axis.is_empty() or _ecu_rpm_axis.is_empty():
		return 1.0
	var tps := clampf(throttle, 0.0, 1.0) * float(_ecu_tps_axis[_ecu_tps_axis.size() - 1])
	return _interpolate_2d(_ecu_fuel_lambda_map, _ecu_rpm_axis, _ecu_tps_axis, rpm, tps)


func ecu_ignition_advance_deg(base_advance: float) -> float:
	if _ecu_ignition_map.is_empty() or _ecu_map_axis.is_empty() or _ecu_rpm_axis.is_empty():
		return base_advance
	var map_raw := clampf(intake.pressure / Cylinder.P0 * float(_ecu_map_axis[_ecu_map_axis.size() - 1]), float(_ecu_map_axis[0]), float(_ecu_map_axis[_ecu_map_axis.size() - 1]))
	return clampf(_interpolate_2d(_ecu_ignition_map, _ecu_rpm_axis, _ecu_map_axis, rpm, map_raw), -10.0, 55.0)


func ecu_speed_limited() -> bool:
	return _ecu_speed_limit_kmh > 0.0 and speed * 3.6 >= _ecu_speed_limit_kmh


static func _interpolate_index(values: Array, fraction: float) -> float:
	if values.is_empty():
		return 0.0
	var position := clampf(fraction, 0.0, 1.0) * float(values.size() - 1)
	var left := int(floor(position))
	var right := mini(left + 1, values.size() - 1)
	return lerpf(float(values[left]), float(values[right]), position - left)


static func _interpolate_axis(values: Array, axis: Array, value: float) -> float:
	if values.is_empty() or values.size() != axis.size():
		return 0.0
	if value <= float(axis[0]):
		return float(values[0])
	if value >= float(axis[axis.size() - 1]):
		return float(values[values.size() - 1])
	for i in range(axis.size() - 1):
		var lo := float(axis[i])
		var hi := float(axis[i + 1])
		if value <= hi:
			return lerpf(float(values[i]), float(values[i + 1]), (value - lo) / (hi - lo))
	return float(values[values.size() - 1])


static func _interpolate_2d(table: Array, x_axis: Array, y_axis: Array, x: float, y: float) -> float:
	if table.is_empty() or x_axis.is_empty() or y_axis.is_empty():
		return 0.0
	var x_left := _axis_lower_index(x_axis, x)
	var y_lower := _axis_lower_index(y_axis, y)
	var x_right := mini(x_left + 1, x_axis.size() - 1)
	var y_upper := mini(y_lower + 1, y_axis.size() - 1)
	var x0 := float(x_axis[x_left])
	var x1 := float(x_axis[x_right])
	var y0 := float(y_axis[y_lower])
	var y1 := float(y_axis[y_upper])
	var fx := 0.0 if x1 == x0 else clampf((x - x0) / (x1 - x0), 0.0, 1.0)
	var fy := 0.0 if y1 == y0 else clampf((y - y0) / (y1 - y0), 0.0, 1.0)
	var v00 := float(table[y_lower][x_left])
	var v01 := float(table[y_lower][x_right])
	var v10 := float(table[y_upper][x_left])
	var v11 := float(table[y_upper][x_right])
	return lerpf(lerpf(v00, v01, fx), lerpf(v10, v11, fx), fy)


static func _axis_lower_index(axis: Array, value: float) -> int:
	if value <= float(axis[0]):
		return 0
	var last := axis.size() - 1
	if value >= float(axis[last]):
		return maxi(last - 1, 0)
	for index in range(last):
		if value <= float(axis[index + 1]):
			return index
	return maxi(last - 1, 0)


# Timed ignition cut: at the redline the spark is held off for LIMITER_CUT_TIME, then tried again.
func _update_limiter(dt: float, redline: float) -> void:
	if _limiter_time > 0.0:
		_limiter_time -= dt
	elif rpm >= redline:
		_limiter_time = LIMITER_CUT_TIME
	intake.limiter_cut = _limiter_time > 0.0


# Builds one Cylinder per cylinder, each started at its own firing angle. Rebuilt only when the geometry changes.
func _build_cylinders(spec: EngineSpec) -> void:
	var is_two_stroke := spec.stroke_type == "two_stroke"
	var key := "%s|%d|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s" % [is_two_stroke, spec.cylinders, spec.bore_mm, spec.stroke_mm, spec.compression_ratio, spec.twin_pin_deg, spec.crossplane, spec.rod_ratio, spec.header, str(FiringOrders.for_spec(spec)), str([spec.intake_centre_deg, spec.intake_duration_deg, spec.intake_lift_mm, spec.exhaust_centre_deg, spec.exhaust_duration_deg, spec.exhaust_lift_mm, spec.cam_lobe_profile, spec.intake_lobe_profile, spec.exhaust_lobe_profile, spec.intake_open_ramp_deg, spec.intake_close_ramp_deg, spec.exhaust_open_ramp_deg, spec.exhaust_close_ramp_deg, spec.intake_duration_050_deg, spec.exhaust_duration_050_deg]), str([spec.intake_valve_mm, spec.exhaust_valve_mm, spec.runner_length_m, spec.runner_bore_mm, spec.wall_heat_scale, spec.valve_cd])]
	if key == _cyl_key:
		return
	_cyl_key = key
	var fire := FiringOrders.for_spec(spec)
	cylinders.clear()
	for i in spec.cylinders:
		if is_two_stroke:
			var c := TwoStrokeCylinder.new()
			c.setup(spec)
			c.start_at(-fire[i])
			cylinders.append(c)
		else:
			var c := Cylinder.new()
			c.setup(spec.bore_mm, spec.stroke_mm, spec.compression_ratio, spec.reciprocating_kg(), spec.rod_over_crank_radius())
			c.set_cams(spec)
			c.start_at(-fire[i])
			cylinders.append(c)
	exhaust = ExhaustGas.new()
	exhaust.build(_audio_layout if _audio_layout != null else ExhaustLayout.build(spec))


# Cold oil shears harder. At and above the operating temperature the scale is 1, which is the friction the dyno was calibrated with.
static func oil_friction_scale(oil_temp_c: float, operating_c: float) -> float:
	if oil_temp_c >= operating_c - 0.5:
		return 1.0
	return 1.0 + 0.8 * (operating_c - oil_temp_c) / maxf(operating_c - 20.0, 1.0)


# Degrees the knock margin loses once the coolant is hotter than 95 °C. None at a normal 90 °C operating point.
static func coolant_knock_penalty_deg(coolant_temp_c: float) -> float:
	return maxf(coolant_temp_c - 95.0, 0.0) * 0.04


# First-order warm-up. Combustion heat only counts while the fluid is still below its operating temperature, so a hot start stays put.
func _warm_fluids(dt: float, spec: EngineSpec) -> void:
	if not _fluids_set:
		oil_c = spec.oil_temp_c
		coolant_c = spec.coolant_temp_c
		_fluids_set = true
	var burn_w := fuel_flow * 0.001 * fuel.lhv
	var oil_gap := maxf(spec.oil_operating_c - oil_c, 0.0)
	oil_c = minf(oil_c + (oil_gap / 80.0 + (burn_w * 0.000015 if oil_gap > 0.0 else 0.0)) * dt, spec.oil_operating_c)
	var cool_gap := maxf(spec.coolant_operating_c - coolant_c, 0.0)
	coolant_c = minf(coolant_c + (cool_gap / 50.0 + (burn_w * 0.00002 if cool_gap > 0.0 else 0.0)) * dt, spec.coolant_operating_c)


# How far the ignition can be advanced past the stock map before the engine knocks, degrees.
static func knock_limit_deg(octane: float, compression_ratio: float) -> float:
	return KNOCK_BASE_DEG + KNOCK_PER_OCTANE_DEG * (octane - 95.0) - KNOCK_PER_CR_DEG * (compression_ratio - 10.0)


# Kelvin the intake air cools by when fuel evaporates in it, at this mixture.
static func charge_cooling_k(latent: float, afr: float, lambda: float) -> float:
	return CHARGE_EVAP_FRACTION * latent / (afr * lambda) / Cylinder.CP


static func clutch_grip(pull: float) -> float:
	return clampf((CLUTCH_BITE_END - pull) / (CLUTCH_BITE_END - CLUTCH_BITE_START), 0.0, 1.0)


# Most torque the clutch pack can carry when fully engaged, N·m. About 25 N·m with the estimates above.
# If gearbox_load is negative (engine braking), apply slipper clutch reduction.
func clutch_capacity(spec: EngineSpec, drive_load: float = 0.0) -> float:
	var base := maxf(CLUTCH_MU * CLUTCH_SPRING_N * CLUTCH_MEAN_R * CLUTCH_FACES, spec.displacement_cc * CLUTCH_NM_PER_CC)
	if spec.clutch_capacity_nm > 0.0:
		base = spec.clutch_capacity_nm
	if drive_load < 0.0 and spec.slipper_clutch:
		return base * SLIPPER_CLUTCH_RAMP
	return base


static func clutch_transfer_torque(free_omega: float, free_speed: float, inertia: float, vehicle_mass: float,
		ratio: float, radius: float, capacity: float, dt: float, stiffness: float = INF) -> float:
	if ratio <= 0.0 or capacity <= 0.0 or dt <= 0.0:
		return 0.0
	var drive := ratio / radius
	var slip := free_omega - free_speed * drive
	var efficiency := DRIVE_EFFICIENCY if slip >= 0.0 else 1.0 / DRIVE_EFFICIENCY
	var inverse_inertia := 1.0 / inertia + drive * drive * efficiency / vehicle_mass
	return clampf(slip / (dt * inverse_inertia + (1.0 / stiffness if is_finite(stiffness) and stiffness > 0.0 else 0.0)), -capacity, capacity)


func _advance_driveline(dt: float, spec: EngineSpec, net: float, inertia: float, ratio: float, radius: float) -> void:
	var mass := cell_mass_kg if cell_mass_kg > 0.0 else spec.road_mass_kg()
	var effective_mass := mass + spec.wheel_equivalent_kg()
	var road_load := 0.0 if cell_mass_kg > 0.0 else road_resistance(speed, mass, spec.drag_area_m2)
	var free_speed := maxf(speed - (road_load + BRAKE_FORCE * brake + cell_load_n) * dt / effective_mass, 0.0)
	var free_omega := maxf(omega + net / inertia * dt, 0.0)
	var cap := clutch_capacity(spec, gearbox_load) * clutch_engage * clutch_engage
	var transfer := clutch_transfer_torque(free_omega, free_speed, inertia, effective_mass, ratio, radius, cap, dt, CLUTCH_STIFFNESS)
	gearbox_load = transfer
	omega = maxf(free_omega - transfer * dt / inertia, 0.0)
	var efficiency := DRIVE_EFFICIENCY if transfer >= 0.0 else 1.0 / DRIVE_EFFICIENCY
	speed = maxf(free_speed + transfer * ratio / radius * efficiency * dt / effective_mass, 0.0)


func _accumulate_cycle(shaft_torque: float, degrees: float, dt: float, cycle_degrees: float) -> void:
	if degrees <= 0.0:
		return
	var left := degrees
	while left > 0.0000001:
		var part := minf(left, cycle_degrees - _rev_deg)
		_rev_tq += shaft_torque * part
		_rev_time += dt * part / degrees
		_rev_deg += part
		left -= part
		if _rev_deg >= cycle_degrees - 0.0000001:
			cycle_brake_torque = _rev_tq / cycle_degrees
			cycle_mean_rpm = cycle_degrees / (6.0 * _rev_time)
			cycle_index += 1
			cycle_ready = true
			_rev_deg = 0.0
			_rev_tq = 0.0
			_rev_time = 0.0


# Aero drag plus rolling resistance, newtons, opposing the bike's motion.
func road_resistance(v: float, mass: float, drag_area: float = DRAG_CDA) -> float:
	return 0.5 * AIR_DENSITY * drag_area * v * v + ROLLING_COEFF * mass * GRAVITY


static func tire_radius_m(spec: EngineSpec = null) -> float:
	if spec != null and spec.vehicle_type != "car" and spec.rear_tire_width_mm > 0.0:
		return (spec.rear_rim_in * 25.4 * 0.5 + spec.rear_tire_width_mm * spec.rear_tire_aspect) * 0.001
	return spec.wheel_radius_m if spec != null and spec.wheel_radius_m > 0.0 else Drivetrain.tire_outer_radius() * 0.1


# Figures from the EngineMetrics module, kept under the old names.
func exhaust_temp_c() -> float:
	return EngineMetrics.exhaust_temp_c(self)

func chamber_peak_c() -> float:
	return EngineMetrics.chamber_peak_c(self)

func port_temps_c() -> Array:
	return EngineMetrics.port_temps_c(self)

func o2_lambda() -> float:
	return EngineMetrics.o2_lambda(self)

func swept_m3() -> float:
	return EngineMetrics.swept_m3(self)

func imep_pa() -> float:
	return EngineMetrics.imep_pa(self)

func bmep_pa() -> float:
	return EngineMetrics.bmep_pa(self)

func fmep_pa() -> float:
	return EngineMetrics.fmep_pa(self)

func indicated_power_w() -> float:
	return EngineMetrics.indicated_power_w(self)

func brake_power_w() -> float:
	return EngineMetrics.brake_power_w(self)

func bsfc_g_kwh() -> float:
	return EngineMetrics.bsfc_g_kwh(self)

func isfc_g_kwh() -> float:
	return EngineMetrics.isfc_g_kwh(self)

func brake_thermal_efficiency() -> float:
	return EngineMetrics.brake_thermal_efficiency(self)

func indicated_thermal_efficiency() -> float:
	return EngineMetrics.indicated_thermal_efficiency(self)

func _thermal_efficiency(power_w: float) -> float:
	return EngineMetrics._thermal_efficiency(self, power_w)

func volumetric_efficiency() -> float:
	return EngineMetrics.volumetric_efficiency(self)

func mechanical_efficiency() -> float:
	return EngineMetrics.mechanical_efficiency(self)

func peak_pressure_pa() -> float:
	return EngineMetrics.peak_pressure_pa(self)

func peak_dp_dtheta() -> float:
	return EngineMetrics.peak_dp_dtheta(self)

func ca50_deg() -> float:
	return EngineMetrics.ca50_deg(self)

func burn_10_90_deg() -> float:
	return EngineMetrics.burn_10_90_deg(self)

func ivc_temp_c() -> float:
	return EngineMetrics.ivc_temp_c(self)

func residual_fraction() -> float:
	return EngineMetrics.residual_fraction(self)

func _mean_angle(pick: Callable) -> float:
	return EngineMetrics._mean_angle(self, pick)
