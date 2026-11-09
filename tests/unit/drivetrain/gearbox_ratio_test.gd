extends SceneTree

var _fails := 0

func _init() -> void:
	var gearbox := Gearbox.new()
	gearbox.gear_ratios = [4.0, 3.0, 2.0, 1.6, 1.3, 1.0, 0.8]
	gearbox.gear = 6
	gearbox.shift_up()
	check(gearbox.gear == 7 and is_equal_approx(gearbox.ratio(), 0.8), "seventh gear selects its ratio")
	gearbox.shift_up()
	check(gearbox.gear == 7, "upshift stays at the highest gear")
	gearbox.shift_down()
	check(gearbox.gear == 6, "seventh gear downshifts to sixth")
	var spec := EngineSpec.new()
	spec.gear_ratios = gearbox.gear_ratios
	var sim := EngineSim.new()
	var dyno := DynoTest.new()
	dyno.start(spec, sim)
	check(dyno.result().gears.size() == 7, "dyno allocates all seven gears")
	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)

func check(ok: bool, message: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + message)