class_name EngineAir
extends RefCounted

# Intake manifold: the throttle plate and idle bypass feed one lumped pressure, which the cylinders draw from.
# The cylinders themselves, with their valves, fuel and burn, are in Cylinder.

const P0 := 101325.0 # atmosphere, Pa
const T0 := 300.0 # intake air temperature, K
const R_AIR := 287.0 # J/(kg·K)
const GAMMA := 1.4
const CD := 0.8 # discharge coefficient for plate and bypass orifices
const THROTTLE_BORE_MM := 30.0 # placeholder, not verified for the CBR150R, drawing uses the same value
const THROTTLE_AREA := PI * 0.015 * 0.015 # from THROTTLE_BORE_MM
const BYPASS_AREA := PI * 0.00087 * 0.00087 # idle bypass radius, 0.87 mm: about 0.45 g/s of idle air for a 150 cc engine (a rough physical estimate)
const MANIFOLD_VOLUME := 5e-4 # m³, manifold plus airbox
const MIN_PRESSURE := 5000.0 # Pa, a floor so the vacuum stays finite

var pressure := P0 # intake manifold pressure, Pa
var bypass_area := BYPASS_AREA # idle bypass for this engine, m²; the simulator scales it with displacement
var limiter_cut := false # true while the rev limiter has the spark cut, set by EngineSim


# Spark advance before top dead centre, degrees: the advance that puts the burn centre (50% burnt) at CA50_TARGET degrees
# after TDC, which is where torque is best. It follows our own burn duration, so the burn centre stays put at every speed.
# (engine-sim's speed-only timing map was tried and dropped: it was tuned for that simulator's much slower burn at high
# speed, and in our burn model it pulls the burn centre to 40 degrees before TDC at 15,000 rpm.) The ECU adds its idle trim.
static func spark_advance_deg(rpm: float, offset := 0.0) -> float: # offset: the rider's advance (+) or retard (-), degrees
	return Cylinder.burn_duration_deg(rpm) * Cylinder.WIEBE_CA50 - Cylinder.CA50_TARGET + offset


# Moves the manifold for dt seconds: throttle and bypass inflow, drawn_kg_s out to the cylinders.
func manifold_update(dt: float, throttle: float, drawn_kg_s: float) -> void:
	var plate_area := THROTTLE_AREA * (1.0 - cos(throttle * PI / 2.0))
	var inflow := _orifice(plate_area) + _orifice(bypass_area)
	pressure = clampf(pressure + R_AIR * T0 / MANIFOLD_VOLUME * (inflow - drawn_kg_s) * dt, MIN_PRESSURE, P0)


# Compressible mass flow through an orifice from atmosphere into the manifold, kg/s.
func _orifice(area: float) -> float:
	var pr := pressure / P0
	if pr >= 1.0 or area <= 0.0:
		return 0.0
	var k := CD * area * P0 / sqrt(R_AIR * T0)
	var critical := pow(2.0 / (GAMMA + 1.0), GAMMA / (GAMMA - 1.0))
	if pr <= critical:
		return k * sqrt(GAMMA * pow(2.0 / (GAMMA + 1.0), (GAMMA + 1.0) / (GAMMA - 1.0)))
	return k * sqrt(2.0 * GAMMA / (GAMMA - 1.0) * (pow(pr, 2.0 / GAMMA) - pow(pr, (GAMMA + 1.0) / GAMMA)))
