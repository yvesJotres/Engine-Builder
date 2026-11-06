class_name EngineSpec
extends Resource

@export var cylinders := 1
@export var displacement_cc := 149.16 # Honda CBR150R (K45N) - exact bore x stroke
@export var bore_mm := 57.3
@export var stroke_mm := 57.8
@export var layout := "inline" # inline | V
@export var bank_angle := 90.0 # V layout only, degrees between banks
@export var rod_ratio := 1.6 # rod length / stroke, single cylinder only
@export var header := "4-2-1" # stock | 4-1 | 4-2-1
@export var fuel := "ron95" # a FuelTank.KINDS entry: ron90, ron92, ron95, ron98 or e85
@export var redline_rpm := 10600.0 # fuel cut-off, per engine: limiter from a press dyno test, not Honda
@export var idle_target_rpm := 1200.0 # rpm the ECU holds at idle
@export var crank_friction_nm := 0.0 # N·m, constant crankshaft friction from the engine-sim reference; 0 leaves it out
@export var flywheel_kg := 2.5 # estimate for the CBR150R, replace with the service manual figure
@export var primary_ratio := 3.26 # crank to mainshaft, K45R (BikesWiki, 2017+ engine, not confirmed for K45R)
@export var final_drive := 3.0 # countershaft to wheel, K45R 45/15 sprockets
@export var gear_ratios: Array = [3.0833, 1.9412, 1.5, 1.2273, 1.0417, 0.9231] # K45R tooth counts, 1st to 6th
@export var twin_pin_deg := 360.0 # 2-cylinder only: crank-pin angle between the two cylinders, 360, 270 or 180
@export var split_pin_v4 := false # 4-cylinder V with a 70 degree split crank pin (Ducati Panigale V4)
@export var crossplane := false # 4-cylinder only: crossplane crank, firing 270/180/90/180 apart (Yamaha R1 family)
@export var fire_deg: Array = [] # wire angle per cylinder from engine-sim's ignition wiring, in its cylinder order; empty = generic order
# Volumetric efficiency scale on the air drawn from the manifold. 1.0 keeps the cylinder model as it is: its own volumetric
# efficiency is already about 90% on the dyno, so a further cut double counts the losses and pulls torque below the published figure.
@export var ve_scale := 1.0
# Lambda target map: target lambda [throttle][rpm]. Rows = throttle 0.0-1.0, cols = RPM 0-redline.
# Richer at high load for combustion cooling. Stoich (1.0) at idle/cruise, ~0.87 at WOT/redline.
@export var lambda_target: Array = [
	[1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00], # 0% throttle
	[1.00, 1.00, 1.00, 1.00, 0.98, 0.96, 0.95, 0.94, 0.93, 0.92], # 10%
	[1.00, 1.00, 0.99, 0.97, 0.95, 0.93, 0.92, 0.91, 0.90, 0.89], # 20%
	[1.00, 0.99, 0.97, 0.95, 0.93, 0.91, 0.90, 0.89, 0.88, 0.87], # 30%
	[0.99, 0.98, 0.95, 0.93, 0.91, 0.89, 0.88, 0.87, 0.87, 0.86], # 40%
	[0.98, 0.96, 0.94, 0.92, 0.90, 0.88, 0.87, 0.86, 0.86, 0.85], # 50%
	[0.97, 0.95, 0.92, 0.90, 0.88, 0.87, 0.86, 0.85, 0.85, 0.85], # 60%
	[0.96, 0.94, 0.91, 0.89, 0.87, 0.86, 0.85, 0.85, 0.85, 0.85], # 70%
	[0.95, 0.93, 0.90, 0.87, 0.86, 0.85, 0.85, 0.85, 0.85, 0.85], # 80%
	[0.94, 0.92, 0.89, 0.86, 0.85, 0.85, 0.85, 0.85, 0.85, 0.85], # 90%
	[0.93, 0.91, 0.88, 0.85, 0.85, 0.85, 0.85, 0.85, 0.85, 0.85], # 100% (WOT)
]
# Valve timing, in crank degrees after firing top dead centre (0 to 720), and lift. Defaults are the stock cams the sim always used.
@export var intake_centre_deg := 470.0 # centre of the intake event (360 to 600): opens 120 deg before it, closes 120 deg after
@export var intake_duration_deg := 240.0 # intake valve open, degrees of crank
@export var intake_lift_mm := 6.0 # intake peak lift
@export var exhaust_centre_deg := 255.0 # centre of the exhaust event
@export var exhaust_duration_deg := 230.0 # exhaust valve open, degrees of crank
@export var exhaust_lift_mm := 5.0 # exhaust peak lift
@export var ignition_offset_deg := 0.0 # ignition advance (+) or retard (-) on top of the engine's timing map, degrees
@export var flywheel_radius_mm := 75.0 # estimate, not a published figure: a light single needs this much inertia to hold idle and rev cleanly
@export var compression_ratio := 11.3 # Honda CBR150R (K45N), dealer page
@export var vehicle_kg := 215.0 # bike and rider, estimate; the CBR250RR preset uses engine-sim's 165 kg
@export var tyre_kg := 8.0 # both tyres, estimate (about 4.5 kg rear, 3.5 kg front); wheel and tyre masses are not published for the K45R
@export var rim_kg := 8.0 # both wheels with brake discs and the rear sprocket, estimate
@export var slant_deg := 20.0 # cylinder lean, degrees, top toward the front. Estimate, not from a manual

@export var piston_kg := 0.09 # piston with rings and pin, estimate
@export var rod_kg := 0.20 # connecting rod, estimate, so crank plus rod is about 2.5 kg
@export var rod_big_fraction := 0.4 # share of the rod's mass at the crank pin, typical split, estimate
@export var balancer_kg := 0.2 # counter-balancer weight on the balancer shaft, estimate (part weight not in the catalogue)

const BALANCER_RADIUS := 0.02 # m, weight centre from the balancer shaft, estimate

# Crankshaft geometry, steel. Webs are modelled as discs around the crank axis, each reaching
# past the crank pin by the pin radius. Dimensions are estimates for a 150 cc single.
const STEEL_DENSITY := 7800.0 # kg/m³
const WEB_THICKNESS := 0.022 # m, set so crank plus rod is about 2.5 kg (catalogue weight)
const PIN_RADIUS := 0.012 # m
const PIN_LENGTH := 0.03 # m
const SHAFT_RADIUS := 0.012 # m
const SHAFT_LENGTH := 0.10 # m


# Crank throw, m. Half the stroke.
func crank_throw_m() -> float:
	return stroke_mm * 0.0005


# Mass of the crankshaft alone, kg: two webs, the crank pin and the shaft.
func crank_mass_kg() -> float:
	var web_r := crank_throw_m() + PIN_RADIUS
	var web_m := STEEL_DENSITY * PI * web_r * web_r * WEB_THICKNESS
	var pin_m := STEEL_DENSITY * PI * PIN_RADIUS * PIN_RADIUS * PIN_LENGTH
	var shaft_m := STEEL_DENSITY * PI * SHAFT_RADIUS * SHAFT_RADIUS * SHAFT_LENGTH
	return 2.0 * web_m + pin_m + shaft_m


# Inertia of the crankshaft about its axis, kg·m²: two webs, the crank pin (offset by the throw), the shaft.
func crank_inertia() -> float:
	var r := crank_throw_m()
	var web_r := r + PIN_RADIUS
	var web_m := STEEL_DENSITY * PI * web_r * web_r * WEB_THICKNESS
	var web_i := 0.5 * web_m * web_r * web_r
	var pin_m := STEEL_DENSITY * PI * PIN_RADIUS * PIN_RADIUS * PIN_LENGTH
	var pin_i := 0.5 * pin_m * PIN_RADIUS * PIN_RADIUS + pin_m * r * r
	var shaft_m := STEEL_DENSITY * PI * SHAFT_RADIUS * SHAFT_RADIUS * SHAFT_LENGTH
	var shaft_i := 0.5 * shaft_m * SHAFT_RADIUS * SHAFT_RADIUS
	return 2.0 * web_i + pin_i + shaft_i


func flywheel_radius_m() -> float:
	return flywheel_radius_mm * 0.001


# Mass that moves up and down with the piston: the piston plus the rod's small end, not rotating.
func reciprocating_kg() -> float:
	return piston_kg + (1.0 - rod_big_fraction) * rod_kg


# Rotating inertia, kg·m²: flywheel ½·m·r², crank webs, the rod's big end at the crank radius,
# and the reciprocating mass as an equivalent rotating mass (½·m·r², averaged over a cycle).
# Rod length over crank radius, the form the cylinder model uses. rod_ratio is rod length over stroke, and the crank
# radius is half the stroke, so the two differ by a factor of two.
func rod_over_crank_radius() -> float:
	return rod_ratio * 2.0


func rotating_inertia() -> float:
	var r := flywheel_radius_m()
	var crank_r := crank_throw_m()
	var flywheel := 0.5 * flywheel_kg * r * r
	var big_end := rod_big_fraction * rod_kg * crank_r * crank_r
	var reciprocating := 0.5 * reciprocating_kg() * crank_r * crank_r
	# the balancer shaft turns with the crank (driven gear, 43T), so its inertia adds to the total
	var balancer := 0.5 * balancer_kg * BALANCER_RADIUS * BALANCER_RADIUS
	return flywheel + crank_inertia() + big_end + reciprocating + balancer


# Mass the wheels add to the bike when it accelerates, kg: their spin inertia divided by the rolling radius squared.
# The tyre mass sits near the outer radius (a ring at 0.95 R), the rim and discs closer in (a ring at 0.7 R).
func wheel_equivalent_kg() -> float:
	return tyre_kg * 0.95 * 0.95 + rim_kg * 0.7 * 0.7


func cylinder_volume_cc() -> float:
	return displacement_cc / cylinders


func calc_displacement_cc() -> float:
	# mm^3 / 1000 = cc
	return PI / 4.0 * bore_mm * bore_mm * stroke_mm * cylinders / 1000.0


# Returns target lambda for given throttle (0-1) and RPM, bilinear interpolation from lambda_target map.
func get_target_lambda(throttle: float, rpm: float) -> float:
	var t := clampf(throttle, 0.0, 1.0)
	var r := clampf(rpm / redline_rpm, 0.0, 1.0)
	var rows := lambda_target.size()
	if rows == 0:
		return 1.0
	var cols: int = lambda_target[0].size()
	if cols == 0:
		return 1.0
	# throttle -> row index (0 to rows-1)
	var ti: float = t * (rows - 1)
	# rpm -> col index (0 to cols-1)
	var ri: float = r * (cols - 1)
	var ti0: int = int(floor(ti))
	var ti1: int = mini(ti0 + 1, rows - 1)
	var ri0: int = int(floor(ri))
	var ri1: int = mini(ri0 + 1, cols - 1)
	var ft: float = ti - ti0
	var fr: float = ri - ri0
	var v00: float = lambda_target[ti0][ri0]
	var v01: float = lambda_target[ti0][ri1]
	var v10: float = lambda_target[ti1][ri0]
	var v11: float = lambda_target[ti1][ri1]
	# bilinear interpolation
	var v0: float = v00 + (v01 - v00) * fr
	var v1: float = v10 + (v11 - v10) * fr
	return v0 + (v1 - v0) * ft


# The first problem with the spec, or "" when it is fine. Shown on the panel as a warning.
func validation_warning() -> String:
	if layout == "V" and cylinders % 2 != 0:
		return "V layout needs an even cylinder count"
	var calc := calc_displacement_cc()
	if absf(calc - displacement_cc) / displacement_cc > 0.02:
		return "Bore x stroke gives %.0f cc, not %.0f cc" % [calc, displacement_cc]
	if intake_duration_deg < 150.0 or intake_duration_deg > 300.0 or exhaust_duration_deg < 150.0 or exhaust_duration_deg > 300.0:
		return "Valve duration must be 150 to 300 degrees"
	if intake_lift_mm < 2.0 or intake_lift_mm > 15.0 or exhaust_lift_mm < 2.0 or exhaust_lift_mm > 15.0:
		return "Valve lift must be 2 to 15 mm"
	if intake_centre_deg < 360.0 or intake_centre_deg > 600.0 or exhaust_centre_deg < 120.0 or exhaust_centre_deg > 360.0:
		return "Valve centre out of range (intake 360 to 600, exhaust 120 to 360)"
	if absf(ignition_offset_deg) > 10.0:
		return "Ignition offset must be within 10 degrees"
	return ""


# Valve event edges, crank degrees after firing top dead centre. The event is centred on the centre angle.
func intake_open_deg() -> float:
	return intake_centre_deg - intake_duration_deg * 0.5


func intake_close_deg() -> float:
	return intake_centre_deg + intake_duration_deg * 0.5


func exhaust_open_deg() -> float:
	return exhaust_centre_deg - exhaust_duration_deg * 0.5


func exhaust_close_deg() -> float:
	return exhaust_centre_deg + exhaust_duration_deg * 0.5
