class_name EngineSpec
extends Resource

@export var cylinders := 1
@export var vehicle_type := "motorcycle"
@export var transmission_type := "manual"
@export var stroke_type := "four_stroke" # "four_stroke" | "two_stroke"
@export var induction := "injection" # how the fuel gets in: "injection" (a nozzle per cylinder) | "carburettor" (a bell with a float bowl, two-strokes)
@export var wheelbase_mm := 1310.0
@export var rider_kg := 75.0
@export var vehicle_mass_includes_rider := true # legacy presets used combined mass; explicit curb-mass presets set false
@export var wheel_radius_m := 0.0
@export var vehicle_length_mm := 0.0
@export var vehicle_width_mm := 0.0
@export var vehicle_height_mm := 0.0
@export var front_track_mm := 0.0
@export var rear_track_mm := 0.0
@export var front_wheel_radius_m := 0.0
@export var front_tire_width_mm := 0.0
@export var rear_tire_width_mm := 0.0
@export var front_tire_aspect := 0.80
@export var rear_tire_aspect := 0.70
@export var front_rim_in := 17.0
@export var rear_rim_in := 17.0
@export var fuel_capacity_l := 12.0
@export var drag_area_m2 := 0.4
@export var max_boost_ratio := 1.0
@export var electric_compressor := false # estimated electric compressor, controlled independently of engine speed
@export var v3r_style := false # V3R-inspired appearance, not a measured replica
@export var compressor_battery_wh := 40.0 # estimated usable electrical energy
@export var compressor_power_w := 2000.0 # estimated power at full boost
@export var compressor_charge_w := 1000.0 # estimated charging power
@export var boost_spool_time := 0.6
@export var compressor_map_id: String = "" # e.g. "garrett_gtx3076r"
@export var compressor_inertia_kgm2: float = 0.00005 # kg·m², compressor+turbine shaft
@export var turbine_a_r: float = 0.63 # turbine housing A/R, for non-electric
@export var wastegate_type: String = "internal" # internal, external, none
@export var wastegate_pressure_ratio: float = 0.0 # PR at which wastegate opens (0 = spring pressure)
@export var turbine_efficiency: float = 0.70 # adiabatic efficiency
@export var intake_area_scale := 1.0
@export var throttle_bore_mm := 30.0 # fallback estimate; override only with a source
@export var throttle_count := 1 # physical butterfly count feeding the lumped manifold
@export var manifold_volume_scale := 1.0
@export var clutch_capacity_nm := 0.0
@export var displacement_cc := 149.16 # Honda CBR150R (K45N) - exact bore x stroke
@export var bore_mm := 57.3
@export var stroke_mm := 57.8
@export var layout := "inline" # inline | V
@export var bank_angle := 90.0 # V layout only, degrees between banks
@export var rod_ratio := 1.6 # rod length / stroke, single cylinder only
@export var header := "4-2-1" # stock | 4-1 | 4-2-1
@export var muffler_style := "stock" # stock | sport | short; approximate dimensions, four-stroke only
@export var live_exhaust_physics := false # experimental 1D pipe solver; higher CPU cost
@export var fuel := "ron95" # a FuelTank.KINDS entry: ron90, ron92, ron95, ron98 or e85
@export var ecu_binary := "" # optional verified ECU flash; unsupported layouts are ignored safely
@export var exhaust_ir_path := "" # custom muffler IR WAV (res://assets/ir/...); empty = auto by layout

# Cam lobe. 0 = half sine. 1 = a cam card: raised cosine between the 0.050 inch points, straight ramps to the seat
# (mgispeedware.com/camshaft-calculator). 2 = a lift table in crank degrees and millimetres.
enum CamLobeProfile { HALF_SINE, CAM_CARD, CUSTOM }
@export var cam_lobe_profile: int = 1 # default to flat-taper for realism
@export var intake_lobe_profile: int = 1 # override per-valve (or -1 to use cam_lobe_profile)
@export var exhaust_lobe_profile: int = 1
# For CUSTOM profile: lift curve as [deg_after_firing_TDC, lift_mm] pairs, 0-720 deg.
# Example: [[350, 0], [380, 2], [420, 6], [460, 6], [500, 2], [530, 0]]
@export var intake_lift_curve: Array = []
@export var exhaust_lift_curve: Array = []
# Kept so an older preset still loads. The cam-card lobe does not use a flat top.
@export var intake_flat_fraction := 0.3
@export var exhaust_flat_fraction := 0.3
# Seat to the 0.050 inch point, crank degrees. 0 uses the calculator's default: the seat is 1.14 times the 0.050 duration.
@export var intake_open_ramp_deg := 0.0
@export var intake_close_ramp_deg := 0.0
@export var exhaust_open_ramp_deg := 0.0
@export var exhaust_close_ramp_deg := 0.0
@export var intake_duration_050_deg := 0.0 # duration at 0.050 inch. 0 derives it from the seat duration
@export var exhaust_duration_050_deg := 0.0

@export var redline_rpm := 10600.0 # fuel cut-off, per engine: limiter from a press dyno test, not Honda
@export var idle_target_rpm := 1200.0 # rpm the ECU holds at idle
@export var crank_friction_nm := 0.0 # N·m, constant crankshaft friction from the engine-sim reference; 0 leaves it out
@export var flywheel_kg := 2.5 # estimate for the CBR150R, replace with the service manual figure
@export var primary_ratio := 3.26 # crank to mainshaft, K45R (BikesWiki, 2017+ engine, not confirmed for K45R)
@export var final_drive := 3.0 # countershaft to wheel, K45R 45/15 sprockets
@export var gear_ratios: Array = [3.0833, 1.9412, 1.5, 1.2273, 1.0417, 0.9231] # K45R tooth counts, 1st to 6th
@export var twin_pin_deg := 360.0 # 2-cylinder only: crank-pin angle between the two cylinders, 360, 270 or 180
@export var split_pin_v4 := false # 4-cylinder V with a 70 degree split crank pin (Ducati Panigale V4)
@export var shared_v_crankpins := false # pair cylinders 1-2, 3-4, etc. on common V-engine crankpins
@export var crossplane := false # 4-cylinder only: crossplane crank, firing 270/180/90/180 apart (Yamaha R1 family)
@export var fire_deg: Array = [] # wire angle per cylinder from engine-sim's ignition wiring, in its cylinder order; empty = generic order
# Rider aids are split into hardware availability and the rider's switch state.
# A preset must explicitly advertise a feature before the panel can enable it.
@export var has_quickshifter := false
@export var has_launch_control := false
@export var has_abs := false
@export var has_traction_control := false
# Quickshifter: cuts ignition/fuel during upshift to unload the gearbox for clutchless shift
@export var quickshifter := false # rider switch, only valid when has_quickshifter
@export var quickshifter_cut_time := 0.05 # s, ignition+fuel cut duration during upshift
@export var quickshifter_cut_profile: Array = [] # per-gear cut time profile: [ [ [rpm, cut_ms], ... ], ... ] for gears 1-6
@export var quickshifter_min_rpm := 3000.0 # rpm above which quickshifter activates
# Downshift blip
@export var quickshifter_blip_time := 0.08 # s, throttle blip duration for clutchless downshift
@export var quickshifter_blip_throttle := 0.3 # throttle fraction during downshift blip
@export var quickshifter_sensitivity := 0.7 # force the shifter needs before it shifts: higher needs a firmer press
@export var quickshifter_flat_shift := false # keep the throttle cracked during the upshift cut instead of closing it
@export var flat_shift_throttle := 0.15 # throttle fraction held during a flat-shift cut
# Power modes: F (Full), M (Mid), L (Low) - changes throttle response and ignition timing
@export var power_mode := "F" # "F", "M", or "L"
# Launch control: holds RPM at launch_rpm while clutch pulled + throttle > launch_throttle + speed < launch_speed
@export var launch_control := false # enable launch control (Kawasaki SE, etc.)
@export var launch_rpm := 8000.0 # target RPM for launch control
@export var launch_throttle := 0.95 # throttle fraction to arm launch control
@export var launch_speed_kmh := 30.0 # speed below which launch control is active (km/h)
# Speed limiter: the voluntary 300 km/h limit most makers fit. The ECU closes the throttle at the limit and the bike holds it.
@export var speed_limit_enabled := false # fit the limiter
@export var speed_limit_kmh := 300.0 # the limit, km/h
# Sound levels from the panel: multipliers on the tuned sound, 1.0 leaves it as it was
@export_range(0.0, 2.0) var sound_valvetrain := 1.0 # valve ticks and cam chain
@export_range(0.0, 2.0) var sound_mechanical := 1.0 # bearing rumble and primary gear whine
@export_range(0.0, 2.0) var sound_driveline := 1.0 # gear whine, clutch rattle, clunk, chain
@export_range(0.0, 2.0) var sound_turbo := 1.0 # whistle, wastegate, blow-off
@export_range(0.0, 2.0) var sound_knock := 1.0 # detonation pings
@export_range(0.0, 2.0) var sound_rasp := 1.0 # rasp noise on the exhaust pulses
@export_range(0.0, 2.0) var sound_intake := 1.0 # intake noise level
@export var abs_enabled := false # rider switch, only valid when has_abs
@export var traction_control_enabled := false # rider switch, only valid when has_traction_control
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
@export var intake_valve_mm := 20.0 # one intake valve head, two valves. 20 mm is the small-single estimate; a published head size replaces it
@export var exhaust_valve_mm := 17.0 # one exhaust valve head, two valves
# The drawing and cam model give every four-stroke two intake and two exhaust valves per cylinder. The sound reads this for
# the valve tick rate; change it only together with the valve model, or the tick and the drawing disagree.
@export var valves_per_cylinder := 4
# Scales this engine's idle bypass on top of the displacement rule. 1.0 is the rule; an engine whose idle air the rule oversupplies sets less.
@export_range(0.05, 2.0) var idle_air_scale := 1.0
@export var runner_length_m := 0.25 # throttle body to the valve. 0.25 m is the small-single estimate; a shorter runner holds its fill to a higher rpm
@export var runner_bore_mm := 0.0 # 0 preserves the legacy 6.6 cm² runner; equivalent bore, not butterfly diameter
@export var intake_display := "stock" # visual option; stock stack dimensions are not verified
@export var velocity_stack_length_mm := 70.0 # visual aftermarket stack length, not a factory dimension
@export var wall_heat_scale := 1.0 # 1 keeps the generic wall-heat estimate. Lower keeps more of the burn as torque on an engine that publishes more than that estimate gives
@export var valve_cd := 0.7 # discharge coefficient of the valve curtain. 0.7 is the small-single estimate
@export var exhaust_centre_deg := 255.0 # centre of the exhaust event
@export var exhaust_duration_deg := 230.0 # exhaust valve open, degrees of crank
@export var exhaust_lift_mm := 5.0 # exhaust peak lift
@export var ignition_offset_deg := 0.0 # ignition advance (+) or retard (-) on top of the engine's timing map, degrees
@export var flywheel_radius_mm := 75.0 # estimate, not a published figure: a light single needs this much inertia to hold idle and rev cleanly
@export var compression_ratio := 11.3 # Honda CBR150R (K45N), dealer page
# Two-stroke specific (ignored when stroke_type == "four_stroke")
@export var crankcase_compression_ratio := 1.5 # crankcase volume / swept volume ratio
@export var transfer_port_open_deg := 120.0 # degrees ATDC when transfer ports open
@export var transfer_port_close_deg := 150.0 # degrees ATDC when transfer ports close (symmetrical)
@export var exhaust_port_open_deg := 90.0 # degrees ATDC when exhaust port opens
@export var exhaust_port_close_deg := 90.0 # degrees ATDC when exhaust port closes (symmetrical)
@export var intake_port_type := "reed" # "reed" | "rotary" | "piston"
@export var intake_port_open_deg := 60.0 # degrees ATDC when intake port opens (reed/rotary)
@export var intake_port_close_deg := 60.0 # degrees ATDC when intake port closes
@export var reed_stiffness := 50000.0 # N/m, reed valve stiffness
@export var reed_damping := 0.5 # reed valve damping coefficient
@export var expansion_chamber := false # enable expansion chamber model
@export var expansion_chamber_length_m := 1.0 # total length of expansion chamber
@export var expansion_chamber_volume_cc := 500.0 # total volume of expansion chamber
@export var oil_injection_ratio := 50.0 # fuel:oil ratio (50 = 50:1)
@export var oil_pump_type := "fixed" # "fixed" | "variable" | "none"
@export var crankcase_volume_cc := 0.0 # auto-calculated if 0
@export var transfer_port_area_mm2 := 0.0 # total transfer port area per cylinder
@export var exhaust_port_area_mm2 := 0.0 # exhaust port area per cylinder
@export var intake_port_area_mm2 := 0.0 # intake/reed area per cylinder
@export var vehicle_kg := 215.0 # bike and rider, estimate; the CBR250RR preset uses engine-sim's 165 kg
@export var tyre_kg := 8.0 # both tyres, estimate (about 4.5 kg rear, 3.5 kg front); wheel and tyre masses are not published for the K45R
@export var rim_kg := 8.0 # both wheels with brake discs and the rear sprocket, estimate
@export var slant_deg := 20.0 # cylinder lean, degrees, top toward the front. Estimate, not from a manual
# Slipper clutch: reduces clutch capacity during engine braking to prevent rear wheel hop
@export var slipper_clutch := false # enable slipper clutch (Kawasaki ZX-25R, etc.)
@export var slipper_ramp := 0.5 # fraction of clutch capacity retained during engine braking (0.5 = 50%)
# The air the correction factor is quoted against. The cylinders still breathe Cylinder.P0 and Cylinder.T0; these numbers
# only turn a finished dyno sheet into an SAE J1349 figure, so a published comparison can say which day it was corrected to.
@export var ambient_pressure_pa := 101325.0
@export var ambient_temp_k := 300.0
@export var relative_humidity := 0.0 # 0 to 1, water vapour taken out of the dry-air pressure in the SAE factor
@export var starter_torque_nm := 0.0 # N·m at zero speed. 0 keeps the 20 N·m per 150 cc estimate
@export var oil_temp_c := 100.0 # °C at the start of a run. 100 is already warm, so a dyno matches a hot engine
@export var coolant_temp_c := 90.0
@export var oil_operating_c := 100.0
@export var coolant_operating_c := 90.0
# Dyno shift. 0 means the test's own default (97% of redline, an 8 s plateau wait, the clutch opened fully).
@export var dyno_shift_fraction := 0.0
@export var dyno_shift_style := "clutch" # clutch: open the lever. flat: a short slip, throttle kept cracked
@export var dyno_rider_skill := 1.0 # 1 feeds the clutch at the normal rate and shifts at dyno_shift_fraction
@export var dyno_plateau_rpm := 0.0 # rpm gained over the plateau window. 0 picks a fine value from the redline
@export var dyno_plateau_after := 0.0 # s in a gear before a flat rpm trace ends it. 0 uses 8 s

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


func road_mass_kg() -> float:
	return maxf(vehicle_kg + (0.0 if vehicle_mass_includes_rider else maxf(rider_kg, 0.0)), 1.0)


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
	if runner_bore_mm < 0.0 or runner_bore_mm > 100.0 or not is_finite(runner_bore_mm):
		return "Runner bore must be 0 (legacy) or up to 100 mm"
	if layout == "W" and cylinders % 4 != 0:
		return "W layout needs a multiple of four cylinders"
	if layout == "V" and cylinders < 2:
		return "V layout needs at least two cylinders"
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
	# Cam profile validation
	if intake_lobe_profile == CamLobeProfile.CUSTOM and intake_lift_curve.size() < 4:
		return "CUSTOM intake lift curve needs at least 4 points"
	if exhaust_lobe_profile == CamLobeProfile.CUSTOM and exhaust_lift_curve.size() < 4:
		return "CUSTOM exhaust lift curve needs at least 4 points"
	if intake_flat_fraction < 0.0 or intake_flat_fraction > 0.8:
		return "intake_flat_fraction must be 0.0 to 0.8"
	if exhaust_flat_fraction < 0.0 or exhaust_flat_fraction > 0.8:
		return "exhaust_flat_fraction must be 0.0 to 0.8"
	if intake_open_ramp_deg < 0.0 or intake_open_ramp_deg > intake_duration_deg * 0.5:
		return "intake_open_ramp_deg must be 0 to half duration"
	if intake_close_ramp_deg < 0.0 or intake_close_ramp_deg > intake_duration_deg * 0.5:
		return "intake_close_ramp_deg must be 0 to half duration"
	if exhaust_open_ramp_deg < 0.0 or exhaust_open_ramp_deg > exhaust_duration_deg * 0.5:
		return "exhaust_open_ramp_deg must be 0 to half duration"
	if exhaust_close_ramp_deg < 0.0 or exhaust_close_ramp_deg > exhaust_duration_deg * 0.5:
		return "exhaust_close_ramp_deg must be 0 to half duration"
	if intake_duration_050_deg > 0.0 and (intake_duration_050_deg < 80.0 or intake_duration_050_deg > intake_duration_deg):
		return "intake duration at 0.050 inch must sit inside the seat duration"
	if exhaust_duration_050_deg > 0.0 and (exhaust_duration_050_deg < 80.0 or exhaust_duration_050_deg > exhaust_duration_deg):
		return "exhaust duration at 0.050 inch must sit inside the seat duration"
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


# Crank angle where the valve reaches 0.050 inch on the way open, degrees after firing top dead centre.
func intake_050_open_deg() -> float:
	return intake_open_deg() + seat_ramps(intake_duration_deg, intake_duration_050_deg, intake_open_ramp_deg, intake_close_ramp_deg).x


func intake_050_close_deg() -> float:
	return intake_close_deg() - seat_ramps(intake_duration_deg, intake_duration_050_deg, intake_open_ramp_deg, intake_close_ramp_deg).y


func exhaust_050_open_deg() -> float:
	return exhaust_open_deg() + seat_ramps(exhaust_duration_deg, exhaust_duration_050_deg, exhaust_open_ramp_deg, exhaust_close_ramp_deg).x


func exhaust_050_close_deg() -> float:
	return exhaust_close_deg() - seat_ramps(exhaust_duration_deg, exhaust_duration_050_deg, exhaust_open_ramp_deg, exhaust_close_ramp_deg).y


# Degrees from the seat to the 0.050 inch point. Explicit ramps win. Otherwise the seat is 1.14 times the 0.050 duration.
static func seat_ramps(seat_deg: float, duration_050: float, open_ramp: float, close_ramp: float) -> Vector2:
	if open_ramp > 0.0 or close_ramp > 0.0:
		var opening := open_ramp if open_ramp > 0.0 else close_ramp
		var closing := close_ramp if close_ramp > 0.0 else open_ramp
		var cap := seat_deg * 0.45
		return Vector2(minf(opening, cap), minf(closing, cap))
	var at_050 := duration_050 if duration_050 > 0.0 else seat_deg / 1.14
	at_050 = clampf(at_050, seat_deg * 0.5, seat_deg)
	var ramp := (seat_deg - at_050) * 0.5
	return Vector2(ramp, ramp)
