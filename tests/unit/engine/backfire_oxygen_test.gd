extends SceneTree

# Fuel only bangs in the pipe if the charge that carried it still had air to burn it. This is what makes a real decel crackle
# irregular - a rich charge with no oxygen passes as hydrocarbons - and it is what the model was missing when every cycle at a
# hot, rich overrun popped on a metronome.
# Run: godot --headless --path . --quit-after 3000 -s res://tests/unit/engine/backfire_oxygen_test.gd

const AFR := 14.7

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func _pop_energy(fuel_kg: float, air_kg: float) -> float:
	var c := Cylinder.new()
	c.setup(50.0, 31.8, 11.5, 0.09, 2.0) # a 250 four, geometry not important here
	var tank := FuelTank.new()
	tank.set_kind("ron95")
	c.start_at(c.exhaust_open - 5.0)
	c._port_heat = 1100.0 # a glowing port
	c.fuel_unburnt_kg = fuel_kg
	c.last_fresh_kg = air_kg
	for i in 2:
		c.advance(5.0, 5.0 / (6.0 * 6000.0), 101325.0, 300.0, -15.0, true, tank, 1.0, true, false, Cylinder.P0, Cylinder.T0)
	return c.backfire_j


func _init() -> void:
	var tank := FuelTank.new()
	tank.set_kind("ron95")
	var lhv := tank.lhv

	# no air at all: the fuel is a hydrocarbon load in the pipe, not a bang
	var dry := _pop_energy(3.0e-5, 0.0)
	print("fuel 30 mg, no air:        %.1f J" % dry)
	check(dry == 0.0, "a charge with no oxygen does not bang (%.1f J)" % dry)

	# air-limited: 1e-4 kg of air can burn 1e-4/14.7 = 6.8e-6 kg of fuel, less than the 30 mg of fuel present
	var limited := _pop_energy(3.0e-5, 1.0e-4)
	var expect_limited := (1.0e-4 / AFR) * lhv * Cylinder.BACKFIRE_BURN
	print("fuel 30 mg, 100 mg air:    %.1f J (air allows %.1f J)" % [limited, expect_limited])
	check(absf(limited - expect_limited) < expect_limited * 0.02,
		"the bang is limited by the air, not the fuel (%.1f vs %.1f J)" % [limited, expect_limited])

	# fuel-limited: only 2 mg of fuel against plenty of air -> all of it can burn
	var rich_air := _pop_energy(2.0e-6, 1.0e-4)
	var expect_rich := 2.0e-6 * lhv * Cylinder.BACKFIRE_BURN
	print("fuel 2 mg, 100 mg air:     %.1f J (fuel allows %.1f J)" % [rich_air, expect_rich])
	check(absf(rich_air - expect_rich) < expect_rich * 0.02,
		"with plenty of air the fuel sets the bang (%.1f vs %.1f J)" % [rich_air, expect_rich])

	# more air, a bigger bang: the crackle varies with the charge instead of repeating itself
	var small := _pop_energy(1.0e-5, 3.0e-5)
	var big := _pop_energy(1.0e-5, 9.0e-5)
	print("same fuel, 30 mg air: %.1f J, 90 mg air: %.1f J (x%.2f)" % [small, big, big / maxf(small, 1.0e-9)])
	check(big > small * 2.5, "three times the air is about three times the bang (%.1f -> %.1f J)" % [small, big])

	print("backfire_oxygen_test: %s" % ("PASS" if _fails == 0 else "FAIL"))
	quit(0 if _fails == 0 else 1)
