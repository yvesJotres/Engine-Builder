class_name EngineSpec
extends Resource

@export var cylinders := 1
@export var displacement_cc := 149.2 # Honda CBR150R (K45N) defaults
@export var bore_mm := 57.3
@export var stroke_mm := 57.8
@export var layout := "inline" # inline | V
@export var bank_angle := 90.0 # V layout only, degrees between banks
@export var rod_ratio := 1.6 # rod length / stroke, single cylinder only
@export var header := "4-2-1" # stock | 4-1 | 4-2-1
@export var fuel := "petrol" # petrol | e85 | diesel
@export var redline_rpm := 10600.0 # fuel cut-off, per engine: limiter from a press dyno test, not Honda
@export var idle_target_rpm := 1200.0 # rpm the ECU holds at idle
@export var idle_leak := 1.0 # scale on the idle bypass for this engine, set per engine so the idle lands in the expected range
@export var crank_friction_nm := 0.0 # N·m, constant crankshaft friction from the engine-sim reference; 0 leaves it out
@export var flywheel_kg := 2.5 # estimate for the CBR150R, replace with the service manual figure
@export var primary_ratio := 3.26 # crank to mainshaft, K45R (BikesWiki, 2017+ engine, not confirmed for K45R)
@export var final_drive := 3.0 # countershaft to wheel, K45R 45/15 sprockets
@export var gear_ratios: Array = [3.0833, 1.9412, 1.5, 1.2273, 1.0417, 0.9231] # K45R tooth counts, 1st to 6th
@export var twin_pin_deg := 360.0 # 2-cylinder only: crank-pin angle between the two cylinders, 360, 270 or 180
@export var crossplane := false # 4-cylinder only: crossplane crank, firing 270/180/90/180 apart (Yamaha R1 family)
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


# Returns "" when the inputs agree. Warns instead of silently fixing a mismatch.
func validation_warning() -> String:
	if layout == "V" and cylinders % 2 != 0:
		return "V layout needs an even cylinder count"
	var calc := calc_displacement_cc()
	if absf(calc - displacement_cc) / displacement_cc > 0.02:
		return "Bore x stroke gives %.0f cc, not %.0f cc" % [calc, displacement_cc]
	return ""
