class_name FuelTank
extends RefCounted

# Fuel properties (SI) and a tank that the engine draws from.
# afr: stoichiometric air-fuel ratio by mass. lhv: lower heating value, J/kg. latent: heat of evaporation, J/kg.
# octane: research octane number (RON), which sets how far the ignition can be advanced before the engine knocks.
# The petrol grades (RON 90, 92, 95, 98) share gasoline's chemistry and differ only in octane.
# E85 is 80% ethanol by mass with 20% gasoline. Its values are the mass-weighted blend of the two components below, so
# fuel_chemistry_test checks them against the components:
#   ethanol:  afr 9.0, lhv 26.8 MJ/kg, latent 840 kJ/kg, density 789 kg/m3, octane 108
#   gasoline: afr 14.7, lhv 44 MJ/kg, latent 350 kJ/kg, density 745 kg/m3, octane 95
const TANK_LITRES := 12.0
const PROPERTIES := {
	"ron90": {"afr": 14.7, "lhv": 44e6, "density": 745.0, "latent": 350e3, "octane": 90.0},
	"ron92": {"afr": 14.7, "lhv": 44e6, "density": 745.0, "latent": 350e3, "octane": 92.0},
	"ron95": {"afr": 14.7, "lhv": 44e6, "density": 745.0, "latent": 350e3, "octane": 95.0},
	"ron98": {"afr": 14.7, "lhv": 44e6, "density": 745.0, "latent": 350e3, "octane": 98.0},
	"e85": {"afr": 9.76, "lhv": 30.2e6, "density": 780.0, "latent": 742e3, "octane": 105.0},
}
# The fuel choices in the order the panel lists them, with the labels it shows.
const KINDS := ["ron90", "ron92", "ron95", "ron98", "e85"]
const LABELS := ["RON 90", "RON 92", "RON 95", "RON 98", "E85"]

var kind := "ron95"
var afr: float
var lhv: float
var latent: float
var octane: float
var mass_kg: float


func _init() -> void:
	_apply_kind(kind)
	refill()


# Switching fuel type fills the tank with the new fuel.
func set_kind(new_kind: String) -> void:
	if new_kind != kind:
		_apply_kind(new_kind)
		refill()


func refill() -> void:
	mass_kg = TANK_LITRES * PROPERTIES[kind].density / 1000.0


func fraction() -> float:
	return mass_kg / (TANK_LITRES * PROPERTIES[kind].density / 1000.0)


func _apply_kind(new_kind: String) -> void:
	kind = new_kind
	afr = PROPERTIES[kind].afr
	lhv = PROPERTIES[kind].lhv
	latent = PROPERTIES[kind].latent
	octane = PROPERTIES[kind].octane
