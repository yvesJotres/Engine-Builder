class_name SoundContext
extends RefCounted

# What the sound layers need to know about the engine and the bike. The game fills it in every frame, and every layer reads
# it when it renders a block. Layers never write to it.

var rpm := 0.0 # engine speed
var throttle := 0.0 # rider throttle, 0 closed to 1 wide open
var load := 0.0 # engine load, 0 to 1: how hard the engine is working (0 when the throttle is closed)
var running := false # the engine is firing
var gear := 0 # 0 is neutral, 1 and up are the gears
var gear_ratio := 0.0 # gearbox ratio of the engaged gear, 0 in neutral
var clutch_engage := 1.0 # 0 clutch open, 1 clutch fully engaged
var speed_ms := 0.0 # road speed
var boost_ratio := 1.0 # intake pressure ratio, 1 means no boost
var turbo := false # the bike has a turbocharger or supercharger
var blower := false # the bike has an engine-driven supercharger
var starter := 0.0 # 1 while the starter motor is held, else 0
var gear_whine := 1.0 # the panel level of the primary gear mesh whine
var fire_time := 0.0 # seconds since the engine started firing, 0 while stopped: rpm layers fade in over it
var knock_count := 0 # counts up by one at every knock event
var cylinders := 1
var four_stroke := true
var valves_per_cylinder := 4
var primary_ratio := 1.0 # crank to clutch basket
var final_drive := 3.0 # gearbox output to wheel


# Fills the context from the simulator and the spec. The game, the offline renderer and the audio lab all call this, so the
# layers see the same thing everywhere.
func update_from(sim: EngineSim, spec: EngineSpec, rider_throttle: float) -> void:
	rpm = sim.rpm
	throttle = rider_throttle
	# engine load from the manifold: near vacuum at idle, atmospheric wide open. The throttle alone is not load: a closed
	# throttle on a fast engine still moves air, and the sim has no separate load figure.
	load = clampf((sim.intake.pressure - 35000.0) / 66325.0, 0.0, 1.0)
	running = sim.running
	gear = sim.gear.gear
	gear_ratio = sim.gear.ratio()
	clutch_engage = sim.clutch_engage
	speed_ms = sim.speed
	boost_ratio = sim.intake.boost_ratio
	# a turbocharger or a mechanical blower whistles; the electric compressor has its own whine in the engine sound
	turbo = spec.max_boost_ratio > 1.0 and not spec.electric_compressor
	blower = spec.mechanical_blower
	starter = 1.0 if sim.last_starter_held else 0.0
	knock_count = sim.knock_count
	cylinders = spec.cylinders
	four_stroke = spec.stroke_type == "four_stroke"
	valves_per_cylinder = spec.valves_per_cylinder
	primary_ratio = spec.primary_ratio
	final_drive = spec.final_drive
