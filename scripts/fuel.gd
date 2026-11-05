class_name FuelTank
extends RefCounted

# Fuel properties (SI) and a tank that the engine draws from.
# afr: stoichiometric air-fuel ratio by mass. lhv: lower heating value, J/kg. latent: heat of evaporation, J/kg.
# octane: research octane number, which sets how far the ignition can be advanced before the engine knocks.
# Petrol and E85 values are typical published figures; the evaporation and octane figures are estimates for the sim.
const TANK_LITRES := 12.0
const PROPERTIES := {
	"petrol": {"afr": 14.7, "lhv": 44e6, "density": 745.0, "latent": 350e3, "octane": 95.0},
	"e85": {"afr": 9.8, "lhv": 29.7e6, "density": 780.0, "latent": 900e3, "octane": 105.0},
}

var kind := "petrol"
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
