class_name EngineSim
extends RefCounted

# Whole-bike physics with no scene nodes, so tests can run it directly.
# Each cylinder is a crank-angle gas model (Cylinder) at its firing angle, sharing one intake manifold.
# Crank speed comes from torque balance; the clutch joins the crank to the bike through
# the gear and final drive; the brake and road resistance slow the bike.

const FRICTION_BASE := 0.18 # N·m, rings, valve train and oil shear (pumping loss is in the cylinder model)
const MAIN_BEARING_FRICTION := 0.01 # N·m per main bearing, two bearings, estimate
const BALANCER_FRICTION := 0.005 # N·m, balancer shaft bearings and gear, estimate
const FRICTION_PER_RPM := 0.0003 # N·m per rpm, bearings and oil shear
const SUBSTEPS := 1 # each fixed physics step is taken once
var physics_dt := 1.0 / 3600.0 # s per physics step, set from the pause menu: Accurate 1/3600, Fast 1/1200
const MAX_FRAME_TIME := 0.1 # s, the most real time one frame may add; a hitch must not make the sim run in fast-forward
const MAX_STEPS_PER_FRAME := 400 # a safety limit on the steps one frame can run
var _accumulator := 0.0 # real time not yet simulated, s
const STARTER_TORQUE := 20.0 # N·m per 150 cc at zero speed, fades to zero at CRANK_RPM; scaled from the CBR150R calibration, estimate
const CRANK_RPM := 500.0
const FIRE_RPM := 400.0 # ignition catches the mixture above this speed
const STALL_RPM := 200.0 # below this the mixture no longer ignites
const LIMITER_CUT_TIME := 0.08 # s, spark held off per limiter hit, from engine-sim's ignition module
const DRAG_CDA := 0.55 # m², drag coefficient times frontal area, estimate
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
const DRIVE_EFFICIENCY := 0.93 # gearbox mesh (6 gears, ~1.5% each), primary drive and chain (~3%) together, estimate
const BRAKE_FORCE := 1800.0 # N, both brakes together, estimate (about 0.85 g on 215 kg)
const BRAKE_APPLY_TIME := 0.2 # s, brake lever pulls on over this time

var rpm := 0.0 # engine speed
var omega := 0.0 # crank speed, rad/s
var speed := 0.0 # bike speed, m/s
var running := false # the mixture is lit
var limiter_active := false # the rev limiter has the spark cut
var clutch_engage := 1.0 # 0 = clutch open, 1 = fully engaged
var clutch_pull := 0.0 # 0 to 1 from the clutch lever: 1 = pulled in, 0 = at rest (engaged unless Shift is held)
var brake := 0.0 # 0 = released, 1 = fully applied
var fuel_flow := 0.0 # g/s, last step
var torque := 0.0 # N·m at the crank, shaft torque averaged over the last step
var gear := Gearbox.new()
var intake := EngineAir.new()
var fuel := FuelTank.new()
var cylinders: Array[Cylinder] = []
var _cyl_key := ""
var _limiter_time := 0.0
var ecu := ECU.new()
var _gas_torque := 0.0 # N·m, the gas torque from the last physics step, used in the next crank kick


# Advances the bike by delta seconds of real time, in fixed physics steps. The physics is the same at any frame rate: a
# slow frame runs more steps, not bigger ones.
func step(delta: float, spec: EngineSpec, throttle: float, ignition: bool, starter_held: bool,
		clutch_held: bool, brake_held: bool, lambda: float) -> void:
	_accumulator = minf(_accumulator + delta, MAX_FRAME_TIME)
	var n := 0
	while _accumulator >= physics_dt and n < MAX_STEPS_PER_FRAME:
		_advance(physics_dt, spec, throttle, ignition, starter_held, clutch_held, brake_held, lambda)
		_accumulator -= physics_dt
		n += 1
	if _accumulator >= physics_dt:
		_accumulator = 0.0 # still behind after the step limit: drop the backlog rather than fast-forward


# One fixed physics step of delta seconds.
func _advance(delta: float, spec: EngineSpec, throttle: float, ignition: bool, starter_held: bool,
		clutch_held: bool, brake_held: bool, lambda: float) -> void:
	var clutch_target := 0.0 if clutch_held else 1.0 - clutch_pull
	clutch_engage = move_toward(clutch_engage, clutch_target, delta / (CLUTCH_ENGAGE_TIME if clutch_target > 0.0 else CLUTCH_RELEASE_TIME))
	brake = move_toward(brake, 1.0 if brake_held else 0.0, delta / BRAKE_APPLY_TIME)

	if not ignition or rpm < STALL_RPM:
		running = false
	elif rpm >= FIRE_RPM:
		running = true

	var inertia := spec.rotating_inertia()
	gear.gear_ratios = spec.gear_ratios
	var ratio := spec.primary_ratio * gear.ratio() * spec.final_drive
	var radius := tire_radius_m()
	var h := delta / SUBSTEPS
	var torque_sum := 0.0
	_build_cylinders(spec)
	var fuel_before := fuel.mass_kg
	for _i in SUBSTEPS:
		_update_limiter(h, spec.redline_rpm)
		var friction := FRICTION_BASE + 2.0 * MAIN_BEARING_FRICTION + BALANCER_FRICTION + FRICTION_PER_RPM * rpm
		# constant crankshaft friction: full strength once the crank turns, fading to nothing as it stops
		friction += spec.crank_friction_nm * minf(rpm / 50.0, 1.0)
		# kick first, as engine-sim's NSV solver does: the crank speed moves with the gas torque from the last step
		var net := _gas_torque
		if starter_held and not running:
			# one cylinder's worth of starter per cylinder: each one's compression resists the crank on cranking
			net += STARTER_TORQUE * spec.displacement_cc / 150.0 * clampf(1.0 - rpm / CRANK_RPM, 0.0, 1.0)
		net -= friction

		# clutch: a spring between crank speed and the speed the road asks for, capped
		var clutch_torque := 0.0
		if ratio > 0.0:
			# capacity rises with the square of the lever travel, so the first part of the pull slips gently
			var cap := clutch_capacity(spec) * clutch_engage * clutch_engage
			# implicit in crank speed, so it stays stable at any step size; the explicit form blew up with a light flywheel
			var wheel_crank := speed * ratio / radius
			var omega_free := (inertia * omega + h * (net + CLUTCH_STIFFNESS * wheel_crank)) / (inertia + h * CLUTCH_STIFFNESS)
			clutch_torque = clampf(CLUTCH_STIFFNESS * (omega_free - wheel_crank), -cap, cap)
		omega = maxf(omega + (net - clutch_torque) / inertia * h, 0.0)
		# the driveline loses power both ways: less reaches the wheel when driving, and the wheel gives the crank less when engine braking
		var wheel_force := clutch_torque * ratio / radius
		wheel_force = wheel_force * DRIVE_EFFICIENCY if wheel_force > 0.0 else wheel_force / DRIVE_EFFICIENCY
		speed = maxf(speed + (wheel_force - road_resistance(speed, spec.vehicle_kg) - BRAKE_FORCE * brake) / (spec.vehicle_kg + spec.wheel_equivalent_kg()) * h, 0.0)

		# drift next: the cylinders and the intake see the crank step in smaller sub-steps (the intake fills and empties
		# fast, so one coarse step overshoots), and the average gas torque is used in the next kick
		# the ECU trims the spark advance at idle to hold the idle speed
		ecu.target_rpm = spec.idle_target_rpm
		var ign := 720.0 - (EngineAir.spark_advance_deg(rpm) + ecu.update(h, rpm, throttle, running))
		var gas := 0.0
		var sub := maxi(1, ceili(h / Cylinder.MAX_FLOW_DT))
		var sub_h := h / sub
		for _j in sub:
			var dphi := omega * sub_h * 180.0 / PI
			var drawn := 0.0
			for c in cylinders:
				var res := c.advance(dphi, sub_h, intake.pressure, EngineAir.T0, ign, running and not intake.limiter_cut, fuel, lambda)
				gas += res.x / sub
				drawn += res.y
				intake.bypass_area = EngineAir.BYPASS_AREA * spec.idle_leak # idle air leaking past the closed plate
			intake.bypass_area = EngineAir.BYPASS_AREA * spec.displacement_cc / 149.2 * ecu.air_factor() # idle air scales with displacement; the ECU's idle valve sets the rest
			intake.manifold_update(sub_h, throttle, drawn / sub_h)
		_gas_torque = gas
		torque_sum += gas - friction # shaft torque, what the crank delivers
		rpm = omega * 60.0 / TAU
	fuel_flow = (fuel_before - fuel.mass_kg) * 1000.0 / delta if delta > 0.0 else 0.0
	limiter_active = intake.limiter_cut
	torque = torque_sum / SUBSTEPS


# Timed ignition cut: at the redline the spark is held off for LIMITER_CUT_TIME, then tried again.
func _update_limiter(dt: float, redline: float) -> void:
	if _limiter_time > 0.0:
		_limiter_time -= dt
	elif rpm >= redline:
		_limiter_time = LIMITER_CUT_TIME
	intake.limiter_cut = _limiter_time > 0.0


# Builds one Cylinder per cylinder, each started at its own firing angle. Rebuilt only when the geometry changes.
func _build_cylinders(spec: EngineSpec) -> void:
	var key := "%d|%s|%s|%s|%s|%s|%s" % [spec.cylinders, spec.bore_mm, spec.stroke_mm, spec.compression_ratio, spec.twin_pin_deg, spec.crossplane, spec.rod_ratio]
	if key == _cyl_key:
		return
	_cyl_key = key
	var fire := FiringOrders.fire_angles(spec.cylinders, spec.twin_pin_deg, spec.crossplane)
	cylinders.clear()
	for i in spec.cylinders:
		var c := Cylinder.new()
		c.setup(spec.bore_mm, spec.stroke_mm, spec.compression_ratio, spec.reciprocating_kg(), spec.rod_over_crank_radius())
		# the crank starts at zero, so this cylinder's firing TDC sits at its fire angle
		c.start_at(-fire[i])
		cylinders.append(c)


# Most torque the clutch pack can carry when fully engaged, N·m. About 25 N·m with the estimates above.
func clutch_capacity(spec: EngineSpec) -> float:
	return maxf(CLUTCH_MU * CLUTCH_SPRING_N * CLUTCH_MEAN_R * CLUTCH_FACES, spec.displacement_cc * CLUTCH_NM_PER_CC)


# Aero drag plus rolling resistance, newtons, opposing the bike's motion.
func road_resistance(v: float, mass: float) -> float:
	return 0.5 * AIR_DENSITY * DRAG_CDA * v * v + ROLLING_COEFF * mass * GRAVITY


static func tire_radius_m() -> float:
	return Drivetrain.tire_outer_radius() * 0.1 # scene units are 10 cm
