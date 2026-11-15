class_name ExhaustHeat
extends RefCounted

# How hot an exhaust wall gets, and whether it glows. The gas temperature comes from the simulation; the WALL follows it
# with a lag and sits below it at steady state, because the pipe loses heat to the air as fast as the gas gives it up.
# A wall only glows once it is past a threshold that depends on WHAT IT IS MADE OF: dull red is around 480 C on plain
# steel, 620 C on stainless - low emissivity, so the same visible glow needs more heat in it - and later still on chrome
# trim. The numbers are estimates, stated here so they can be corrected against a real pipe: the model is a first-order
# lag per part, not a heat-transfer solve.
const AMBIENT_C := 20.0
const MATERIALS := {
	# onset_c: where the metal is visibly glowing. full_c: bright orange. lag_s: how fast that part heats.
	# ratio: the wall's steady temperature as a fraction of the gas's.
	"steel": {"onset_c": 480.0, "full_c": 900.0, "lag_s": 6.0, "ratio": 0.82},
	"stainless": {"onset_c": 620.0, "full_c": 1000.0, "lag_s": 9.0, "ratio": 0.80},
	"titanium": {"onset_c": 700.0, "full_c": 1080.0, "lag_s": 5.0, "ratio": 0.78},
	"chrome": {"onset_c": 760.0, "full_c": 1100.0, "lag_s": 10.0, "ratio": 0.76},
}

var material := "steel"
var wall_c := AMBIENT_C


func _init(material_name := "steel") -> void:
	material = material_name if MATERIALS.has(material_name) else "steel"


static func material_of(name: String) -> Dictionary:
	return MATERIALS.get(name, MATERIALS["steel"])


# One step toward the steady wall temperature the gas would hold this part at.
func step(gas_c: float, delta: float) -> void:
	var m := material_of(material)
	var target: float = AMBIENT_C + maxf(gas_c - AMBIENT_C, 0.0) * float(m.ratio)
	wall_c += (target - wall_c) * (1.0 - exp(-maxf(delta, 0.0) / float(m.lag_s)))


# 0 below the material's threshold and 1 at full heat; the strength and colour to add to the metal.
func glow() -> Dictionary:
	var m := material_of(material)
	var onset: float = m.onset_c
	if wall_c <= onset:
		return {"strength": 0.0, "colour": Color(0.0, 0.0, 0.0)}
	var s := clampf((wall_c - onset) / (float(m.full_c) - onset), 0.0, 1.0)
	return {"strength": s, "colour": glow_colour(s)}


# Blackbody through the visible range a pipe actually shows: dull red, cherry, orange, then pale orange.
static func glow_colour(s: float) -> Color:
	s = clampf(s, 0.0, 1.0)
	if s < 0.35:
		return Color(1.0, 0.10, 0.02).lerp(Color(1.0, 0.28, 0.05), s / 0.35)
	if s < 0.7:
		return Color(1.0, 0.28, 0.05).lerp(Color(1.0, 0.50, 0.12), (s - 0.35) / 0.35)
	return Color(1.0, 0.50, 0.12).lerp(Color(1.0, 0.78, 0.40), (s - 0.7) / 0.3)
