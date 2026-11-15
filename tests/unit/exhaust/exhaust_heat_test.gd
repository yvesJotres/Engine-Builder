extends SceneTree

# Exhaust heat glow. A pipe glows when its WALL is hot enough, the wall lags the gas, and what counts as "hot enough"
# depends on the metal: dull red starts at about 480 C on plain steel, 620 C on stainless, later on chrome. Nothing
# glows cold, and nothing glows because the gas passed 600 C for a moment.
# Run: godot --headless --path . -s res://tests/unit/exhaust/exhaust_heat_test.gd   (prints PASS or FAIL)

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


# Hold a gas temperature for `seconds` at 60 Hz and report the wall and the glow.
func _hold(heat: ExhaustHeat, gas_c: float, seconds: float) -> Dictionary:
	for i in int(seconds * 60.0):
		heat.step(gas_c, 1.0 / 60.0)
	return heat.glow()


func _init() -> void:
	await process_frame
	var steel := ExhaustHeat.new("steel")
	var stainless := ExhaustHeat.new("stainless")

	# ---- nothing glows cold, whatever the material ----
	var cold := _hold(steel, 200.0, 60.0)
	print("steel at 200 C gas: wall %.0f C, glow %.3f" % [steel.wall_c, cold.strength])
	check(float(cold.strength) == 0.0, "a cool pipe does not glow")
	check(steel.wall_c < ExhaustHeat.MATERIALS.steel.onset_c, "the wall stays under the threshold (%.0f C)" % steel.wall_c)

	# ---- it takes time: one second of hot gas does not light the pipe ----
	var fresh := ExhaustHeat.new("steel")
	for i in 60:
		fresh.step(900.0, 1.0 / 60.0)
	print("steel after 1 s at 900 C gas: wall %.0f C, glow %.3f" % [fresh.wall_c, fresh.glow().strength])
	check(fresh.wall_c < 900.0 * 0.82 * 0.6, "the wall lags the gas (%.0f C after a second)" % fresh.wall_c)

	# ---- hot enough on steel: it glows, and harder as it gets hotter ----
	steel = ExhaustHeat.new("steel")
	var warm := _hold(steel, 700.0, 60.0)
	var wall_warm := steel.wall_c
	steel = ExhaustHeat.new("steel")
	var hot := _hold(steel, 950.0, 60.0)
	print("steel: 700 C gas -> wall %.0f C, glow %.3f ; 950 C gas -> wall %.0f C, glow %.3f"
		% [wall_warm, warm.strength, steel.wall_c, hot.strength])
	check(float(warm.strength) > 0.0, "a steel header glows at 700 C of gas")
	check(float(hot.strength) > float(warm.strength), "and glows harder when it is hotter")

	# ---- the material decides when ----
	stainless = ExhaustHeat.new("stainless")
	var same := _hold(stainless, 700.0, 60.0)
	print("stainless at the same 700 C gas: wall %.0f C, glow %.3f" % [stainless.wall_c, same.strength])
	check(float(same.strength) < float(warm.strength),
		"the same gas heats stainless to less of a glow (%.3f vs %.3f)" % [same.strength, warm.strength])
	stainless = ExhaustHeat.new("stainless")
	var stainless_hot := _hold(stainless, 1000.0, 90.0)
	check(float(stainless_hot.strength) > 0.0, "stainless does glow once it is hot enough (%.3f)" % stainless_hot.strength)
	var chrome := ExhaustHeat.new("chrome")
	var chrome_glow := _hold(chrome, 1000.0, 90.0)
	check(float(chrome_glow.strength) < float(stainless_hot.strength),
		"chrome needs more heat than stainless for the same glow (%.3f vs %.3f)" % [chrome_glow.strength, stainless_hot.strength])

	# ---- the colour follows the temperature, dull red to orange ----
	var dim := ExhaustHeat.glow_colour(0.1)
	var bright := ExhaustHeat.glow_colour(0.9)
	print("colour at 10%% %.2f,%.2f,%.2f  at 90%% %.2f,%.2f,%.2f" % [dim.r, dim.g, dim.b, bright.r, bright.g, bright.b])
	check(dim.g < bright.g and dim.b <= bright.b, "a dull glow is redder than a hot one")

	# ---- the drawing: parts glow from the sim's exhaust temperature, each by its own material ----
	var spec: EngineSpec = DynoRunner.spec_for("kawasaki_zx25r_se")
	var layout := ExhaustLayout.build(spec)
	var exhaust := Exhaust.new()
	root.add_child(exhaust)
	exhaust.build(layout)
	print("parts drawn: %d (heat states %d)" % [layout.pipes.size(), exhaust.part_count()])
	check(exhaust.part_count() == layout.pipes.size(), "every drawn part has a wall temperature")
	exhaust.update_heat(300.0, 5.0)
	var any_cold := 0.0
	for i in exhaust.part_count():
		any_cold += exhaust.part_glow(i)
	check(any_cold == 0.0, "a cold start draws no glow anywhere (%.3f)" % any_cold)
	for i in 600: # ten seconds of hot gas
		exhaust.update_heat(900.0, 1.0 / 60.0)
	var header_glow := exhaust.part_glow(0)
	var tail_glow := exhaust.part_glow(exhaust.part_count() - 1)
	print("after 10 s at 900 C gas: first part %.2f, last part %.2f, walls %.0f..%.0f C"
		% [header_glow, tail_glow, exhaust.part_wall_c(0), exhaust.part_wall_c(exhaust.part_count() - 1)])
	check(header_glow > 0.0, "the header glows once it is hot")
	check(header_glow > tail_glow, "the header glows harder than the tail, which the gas has left cooler")

	if _fails == 0:
		print("exhaust_heat_test: PASS (no glow cold, glow above the material's threshold, hotter glows harder)")
	quit(0 if _fails == 0 else 1)
