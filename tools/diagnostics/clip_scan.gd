extends SceneTree

# Scans the whole bike for parts inside other parts and prints the worst pairs. Run it after touching any geometry; it is
# the measurement behind tests/unit/drivetrain/clip_test.gd.
#   godot --headless --path . -s res://tools/diagnostics/clip_scan.gd [-- <preset>] [--top N]

# A node path with the instance numbers and the scene-root prefix stripped: Bank0/Flame3 -> Bank/Flame
func _stem(path: String) -> String:
	var stripped := path.replace("/root/", "")
	var re := RegEx.new()
	re.compile("[0-9]+$")
	var parts := stripped.split("/")
	for i in parts.size():
		parts[i] = re.sub(parts[i], "", true) if re.search(parts[i]) != null else parts[i]
	return "/".join(parts)


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var id := "honda_cbr1000rrr_sp"
	var top := 25
	for i in args.size():
		if args[i] == "--top" and i + 1 < args.size():
			top = int(args[i + 1])
		elif Presets.PRESETS.has(str(args[i])):
			id = str(args[i])
	var spec := EngineSpec.new()
	for key in Presets.PRESETS[id].keys():
		spec.set(key, Presets.PRESETS[id][key])

	var model := EngineModel.new()
	model.name = "Engine"
	root.add_child(model)
	model.build(spec)
	var tank := FuelTankModel.new()
	tank.name = "Tank"
	root.add_child(tank)
	tank.place(model.highest_y() + 0.4, (model.crank_position().z + model.throttle_position().z) * 0.5)
	var bounds: AABB = model.chassis_envelope()
	var half_width := maxf(0.85, maxf(absf(bounds.position.x), absf(bounds.end.x)) + 0.25)
	var dt := Drivetrain.new()
	dt.name = "Bike"
	root.add_child(dt)
	dt.build(Ground.Y, GearboxModel.countershaft_position(model.crank_position(), spec), tank.outlet_position(),
		half_width, spec.abs_hardware(), bounds, spec, id)
	var layout := ExhaustLayout.build(spec, model.exhaust_ports(), model.crank_position(), Ground.Y, dt.rear_axle)
	var exhaust := Exhaust.new()
	exhaust.name = "Exhaust"
	root.add_child(exhaust)
	exhaust.build(layout, null)
	await process_frame

	var started := Time.get_ticks_msec()
	var result := ClipCheck.scan([model, dt, exhaust, tank])
	var pairs: Array = result["pairs"]
	if args.has("--write-baseline"):
		var keys := []
		for pair in pairs:
			keys.append("%s|%s" % [pair["a"], pair["b"]])
		keys.sort()
		var file := FileAccess.open("res://tests/fixtures/clip_baseline.json", FileAccess.WRITE)
		file.store_string(JSON.stringify({"pairs": keys}, "\n"))
		file.close()
		print("wrote baseline: %d pairs" % keys.size())
		quit(0)
		return
	print("%s: %d samples, %d clipped pairs, %d ms" % [id, int(result["checked"]), pairs.size(),
		Time.get_ticks_msec() - started])
	# grouped by category: digits stripped, so Bolt0..Bolt9 and Wheel-1/Wheel1 collapse into one row each
	var groups := {}
	for pair in pairs:
		var key := "%s | %s" % [_stem(str(pair["a"])), _stem(str(pair["b"]))]
		if not groups.has(key):
			groups[key] = {"worst": 0.0, "pairs": 0, "verts": 0}
		groups[key]["worst"] = maxf(float(groups[key]["worst"]), float(pair["worst"]))
		groups[key]["pairs"] = int(groups[key]["pairs"]) + 1
		groups[key]["verts"] = int(groups[key]["verts"]) + int(pair["count"])
	var keys := groups.keys()
	keys.sort_custom(func(x, y): return float(groups[x]["worst"]) > float(groups[y]["worst"]))
	for i in mini(top, keys.size()):
		var g: Dictionary = groups[keys[i]]
		print("  %5.0f mm  %-52s %-52s %3d pairs %6d verts" % [float(g["worst"]) * 100.0, keys[i].split(" | ")[0],
			keys[i].split(" | ")[1], int(g["pairs"]), int(g["verts"])])
	quit(0)
