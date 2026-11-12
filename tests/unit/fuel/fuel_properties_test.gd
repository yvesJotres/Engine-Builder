extends SceneTree

# Fuel properties, docs/physics-validation.md section 9 first row, which had no test.
#
# The values live in scripts/fuel/fuel.gd (PROPERTIES). They are checked against the bands cited in
# docs/engine_physics/03_fuel_properties.md:
#   LHV, gasoline   42.9 - 44 MJ/kg    [S] (NPTEL 43.5, IEA AMF 43)
#   AFR, stoich     14.7 by mass
#   density         720 - 775 kg/m3 at 15 C   [S] (IEA AMF)
#   latent heat     350 - 440 kJ/kg
# plus the relations between fuels, which are what a transposed digit breaks: E85 is leaner-burning (lower stoich AFR),
# carries less energy per kg, is denser, and evaporates with more heat taken from the charge.
#
# Tag [table] for the gasoline bands; the cross-fuel ordering is a physical consistency check, not a table value.
# Run: godot --headless --path . -s res://tests/unit/fuel/fuel_properties_test.gd   (exit 1 on failure)

const LHV_LO := 42.9e6
const LHV_HI := 44.0e6
const AFR_GASOLINE := 14.7
const DENSITY_LO := 720.0
const DENSITY_HI := 775.0
const LATENT_LO := 350.0e3
const LATENT_HI := 440.0e3

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func _init() -> void:
	# ---- 1. every gasoline grade sits inside the cited bands ----
	for kind in ["ron90", "ron92", "ron95", "ron98", "ron100"]:
		var tank := FuelTank.new()
		tank.set_kind(kind)
		check(tank.lhv >= LHV_LO and tank.lhv <= LHV_HI,
			"%s: LHV %.2f MJ/kg inside 42.9-44" % [kind, tank.lhv / 1.0e6])
		check(is_equal_approx(tank.afr, AFR_GASOLINE), "%s: stoichiometric AFR is 14.7 (%.2f)" % [kind, tank.afr])
		var density: float = FuelTank.PROPERTIES[kind].density
		check(density >= DENSITY_LO and density <= DENSITY_HI,
			"%s: density %.0f kg/m3 inside 720-775" % [kind, density])
		check(tank.latent >= LATENT_LO and tank.latent <= LATENT_HI,
			"%s: latent heat %.0f kJ/kg inside 350-440" % [kind, tank.latent / 1.0e3])

	# ---- 2. the grades differ only in octane ----
	var ron90 := FuelTank.new()
	ron90.set_kind("ron90")
	var ron98 := FuelTank.new()
	ron98.set_kind("ron98")
	check(is_equal_approx(ron90.lhv, ron98.lhv) and is_equal_approx(ron90.afr, ron98.afr),
		"the octane grades share LHV and AFR; only the knock resistance differs")
	check(float(FuelTank.PROPERTIES["ron90"].octane) < float(FuelTank.PROPERTIES["ron98"].octane), "and the octane number rises with the grade")

	# ---- 3. E85 against gasoline: the four relations a transposed digit breaks ----
	var gas := FuelTank.new()
	gas.set_kind("ron95")
	var e85 := FuelTank.new()
	e85.set_kind("e85")
	check(e85.afr < gas.afr, "E85 burns leaner (AFR %.2f < %.2f)" % [e85.afr, gas.afr])
	check(e85.lhv < gas.lhv, "E85 carries less energy per kg (%.1f < %.1f MJ/kg)" % [e85.lhv / 1.0e6, gas.lhv / 1.0e6])
	check(float(FuelTank.PROPERTIES["e85"].density) > float(FuelTank.PROPERTIES["ron95"].density), "E85 is denser")
	check(e85.latent > gas.latent, "E85 takes more heat to evaporate (%.0f > %.0f kJ/kg)" % [e85.latent / 1.0e3, gas.latent / 1.0e3])
	# published E85 figures: AFR about 9.7-9.8, LHV about 29-30 MJ/kg, density about 780 kg/m3
	check(e85.afr > 9.6 and e85.afr < 9.9, "E85 AFR is in the published 9.7-9.8 band (%.2f)" % e85.afr)
	check(e85.lhv > 29.0e6 and e85.lhv < 31.0e6, "E85 LHV is in the published 29-30 MJ/kg band (%.1f)" % (e85.lhv / 1.0e6))

	# ---- 4. the tank's own bookkeeping follows the density ----
	var t := FuelTank.new()
	t.set_kind("ron95")
	t.set_capacity(15.0)
	check(absf(t.mass_kg - 15.0 * 745.0 / 1000.0) < 1.0e-9, "a full 15 L tank holds %.3f kg of petrol" % t.mass_kg)
	check(absf(t.fraction() - 1.0) < 1.0e-9, "and reads full")
	t.mass_kg = t.capacity_litres * 745.0 / 1000.0 * 0.5
	check(absf(t.fraction() - 0.5) < 1.0e-9, "at half level it reads half")
	# switching fuel re-applies the new fuel's density and stoichiometry (the tank is filled to the new fuel's mass)
	t.set_kind("e85")
	check(is_equal_approx(t.afr, e85.afr), "the stoichiometry follows the new fuel")
	check(absf(t.mass_kg - t.capacity_litres * 780.0 / 1000.0) < 1.0e-9, "and a full tank of E85 holds its own mass (%.3f kg)" % t.mass_kg)

	# ---- 5. evaporative charge cooling ranks with latent/AFR ----
	var cool_gas: float = EngineSim.charge_cooling_k(gas.latent, gas.afr, 1.0)
	var cool_e85: float = EngineSim.charge_cooling_k(e85.latent, e85.afr, 1.0)
	check(cool_gas > 0.0, "petrol cools the charge (%.1f K)" % cool_gas)
	check(cool_e85 > cool_gas, "E85 cools it more (%.1f K > %.1f K)" % [cool_e85, cool_gas])
	# lambda is air/fuel relative to stoichiometric: halving it doubles the fuel, and so the cooling
	check(is_equal_approx(EngineSim.charge_cooling_k(gas.latent, gas.afr, 0.5), 2.0 * cool_gas),
		"a target at lambda 0.5 doubles the fuel and the cooling (%.1f K)" % EngineSim.charge_cooling_k(gas.latent, gas.afr, 0.5))

	print("petrol %.1f MJ/kg, AFR %.2f, %.0f kg/m3, latent %.0f kJ/kg, cooling %.1f K; E85 cooling %.1f K" % [
		gas.lhv / 1.0e6, gas.afr, float(FuelTank.PROPERTIES["ron95"].density), gas.latent / 1.0e3, cool_gas, cool_e85])
	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
