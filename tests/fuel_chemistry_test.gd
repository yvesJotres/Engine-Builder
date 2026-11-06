extends SceneTree

# Checks the fuel properties against their components: E85 is 80% ethanol and 20% gasoline by mass, so its air-fuel ratio,
# heating value, latent heat, density and octane are the mass-weighted blend. Energy per kilogram of air is close for both fuels.
# Run: godot --headless -s tests/fuel_chemistry_test.gd (exit code 1 on failure)

var _fails := 0


func check(ok: bool, msg: String) -> void:
	print(("ok   " if ok else "FAIL ") + msg)
	if not ok:
		_fails += 1


func _near(a: float, b: float, tol: float) -> bool:
	return absf(a - b) <= tol * absf(b)


func _init() -> void:
	await process_frame
	var eth := {"afr": 9.0, "lhv": 26.8e6, "latent": 840e3, "density": 789.0, "octane": 108.0}
	var gas: Dictionary = FuelTank.PROPERTIES["ron95"]
	var e85: Dictionary = FuelTank.PROPERTIES["e85"]
	var f := 0.8 # ethanol share by mass
	# stoichiometric air-fuel ratio of a blend: air per kg of blend = 1 / sum(mass share / afr)
	var afr: float = 1.0 / (f / eth.afr + (1.0 - f) / gas.afr)
	check(_near(e85.afr, afr, 0.01), "E85 air-fuel ratio is the blend's %.2f (table %.2f)" % [afr, e85.afr])
	var lhv: float = f * eth.lhv + (1.0 - f) * gas.lhv
	check(_near(e85.lhv, lhv, 0.01), "E85 heating value is the blend's %.1f MJ/kg (table %.1f)" % [lhv / 1e6, e85.lhv / 1e6])
	var latent: float = f * eth.latent + (1.0 - f) * gas.latent
	check(_near(e85.latent, latent, 0.01), "E85 latent heat is the blend's %.0f kJ/kg (table %.0f)" % [latent / 1e3, e85.latent / 1e3])
	var density: float = f * eth.density + (1.0 - f) * gas.density
	check(_near(e85.density, density, 0.01), "E85 density is the blend's %.0f kg/m3 (table %.0f)" % [density, e85.density])
	var octane: float = f * eth.octane + (1.0 - f) * gas.octane
	check(_near(e85.octane, octane, 0.01), "E85 octane is the blend's %.1f (table %.1f)" % [octane, e85.octane])
	# energy released per kilogram of stoichiometric air: nearly the same for both fuels
	var per_air_petrol: float = gas.lhv / gas.afr
	var per_air_e85: float = e85.lhv / e85.afr
	check(absf(per_air_e85 / per_air_petrol - 1.0) < 0.05, "energy per kg of air is within 5%% on both fuels (%.2f vs %.2f MJ/kg)" % [per_air_e85 / 1e6, per_air_petrol / 1e6])
	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
