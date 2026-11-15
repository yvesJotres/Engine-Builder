extends SceneTree

# Renders the exhaust so it can be judged by eye, not only by numbers: the flanges at the ports, the springs at the
# joints, the lambda boss on the collector, and the canister with its shield and hanger.
# Run windowed (headless has no framebuffer):
#   godot --path . -s res://tools/diagnostics/capture_exhaust.gd [-- <suffix>]

const OUT_DIR := "res://tools/diagnostics/out"
const PRESET := "honda_cbr1000rrr_sp"


func _init() -> void:
	var suffix := ""
	var preset_id := PRESET
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and Presets.PRESETS.has(str(args[0])):
		preset_id = str(args[0])
		suffix = "_" + preset_id
	if args.size() > 1:
		suffix = str(args[1])

	var spec := EngineSpec.new()
	var preset: Dictionary = Presets.PRESETS[preset_id]
	for key in preset.keys():
		spec.set(key, preset[key])

	# build the bike the way main.gd does, so the layout's routing matches the one in game
	var model := EngineModel.new()
	get_root().add_child(model)
	model.build(spec)
	var tank := FuelTankModel.new()
	get_root().add_child(tank)
	tank.place(model.highest_y() + 0.4, (model.crank_position().z + model.throttle_position().z) * 0.5)
	var bounds: AABB = model.chassis_envelope()
	var half_width := maxf(0.85, maxf(absf(bounds.position.x), absf(bounds.end.x)) + 0.25)
	var dt := Drivetrain.new()
	get_root().add_child(dt)
	dt.build(Ground.Y, GearboxModel.countershaft_position(model.crank_position(), spec), tank.outlet_position(),
		half_width, spec.abs_hardware(), bounds, spec, preset_id)
	var layout := ExhaustLayout.build(spec, model.exhaust_ports(), model.crank_position(), Ground.Y, dt.rear_axle)
	var exhaust := Exhaust.new()
	get_root().add_child(exhaust)
	exhaust.build(layout, null)
	await process_frame

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.1, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.64, 0.68, 0.76)
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var world := WorldEnvironment.new()
	world.environment = env
	get_root().add_child(world)

	var cam := Camera3D.new()
	cam.fov = 38.0
	get_root().add_child(cam)
	cam.current = true
	for item in [[Vector3(-35.0, 40.0, 0.0), 1.8], [Vector3(20.0, -140.0, 0.0), 0.8], [Vector3(60.0, 5.0, 0.0), 0.5]]:
		var lamp := DirectionalLight3D.new()
		lamp.rotation_degrees = item[0]
		lamp.light_energy = item[1]
		get_root().add_child(lamp)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var prim: ExhaustLayout.Pipe = null
	var collector: ExhaustLayout.Pipe = null
	var can: ExhaustLayout.Pipe = null
	for pipe in layout.pipes:
		if pipe.kind == "primary" and prim == null:
			prim = pipe
		elif pipe.kind == "collector":
			collector = pipe
		elif pipe.kind == "muffler":
			can = pipe

	# 1. the ports, from the front and outboard, with the bike hidden so the flanges are clear
	var port_point: Vector3 = prim.pts[0]
	for child in dt.get_children():
		child.visible = false
	await _shoot(cam, port_point + Vector3(-2.6, 1.2, 3.2), port_point, "%s/exhaust_ports%s.png" % [OUT_DIR, suffix])

	# 2. the collector, which carries the boss and two springs
	var collector_point: Vector3 = collector.pts[1]
	for child in dt.get_children():
		child.visible = false
	await _shoot(cam, collector_point + Vector3(-3.4, 1.4, 2.6), collector_point, "%s/exhaust_collector%s.png" % [OUT_DIR, suffix])

	# 3. the canister: shield, hanger, springs
	var can_mid: Vector3 = can.pts[0].lerp(can.pts[-1], 0.5)
	await _shoot(cam, can_mid + Vector3(-4.4, 2.0, 2.6), can_mid, "%s/exhaust_canister%s.png" % [OUT_DIR, suffix])

	# 4. the tail mouth, close, so the bore is judged rather than assumed: a hollow pipe shows a dark hole, and the rim
	# shows a bright edge around it
	var tail: ExhaustLayout.Pipe = null
	for pipe in layout.pipes:
		if pipe.kind == "tail":
			tail = pipe
	if tail != null:
		var tip: Vector3 = tail.pts[-1]
		var axis: Vector3 = (tail.pts[-1] - tail.pts[-2]).normalized()
		var side: Vector3 = axis.cross(Vector3.RIGHT).normalized()
		await _shoot(cam, tip + axis * 1.5 + side * 0.55 + Vector3(0.0, 0.15, 0.0), tip,
			"%s/exhaust_mouth%s.png" % [OUT_DIR, suffix])
		# read the picture back: the mouth has to be darker than the rim, or it is not reading as a hole
		var mouth_image := get_root().get_texture().get_image()
		var probes := {"bore opening": tip, "inside the bore": tip - axis * 0.12,
			"rim": tip + side * tail.radii[-1] * 0.98}
		var values := {}
		for label in probes.keys():
			var screen: Vector2 = cam.unproject_position(probes[label])
			var px := mouth_image.get_pixel(int(screen.x), int(screen.y))
			values[label] = 0.299 * px.r + 0.587 * px.g + 0.114 * px.b
		print("  mouth luma: bore %.3f, inside %.3f, rim %.3f" % [
			values["bore opening"], values["inside the bore"], values["rim"]])

	# 5. the whole run, with the bike back, so it is judged in place
	for child in dt.get_children():
		child.visible = true
	var middle: Vector3 = (prim.pts[0] + can.pts[-1]) * 0.5
	await _shoot(cam, middle + Vector3(-9.0, 4.5, 6.0), middle, "%s/exhaust_whole%s.png" % [OUT_DIR, suffix])
	quit(0)


func _shoot(cam: Camera3D, eye: Vector3, target: Vector3, path: String) -> void:
	cam.global_position = eye
	cam.look_at(target, Vector3.UP)
	for i in 3:
		await process_frame
	var image := get_root().get_texture().get_image()
	var err := image.save_png(ProjectSettings.globalize_path(path))
	print("%s: %s" % [path, "saved" if err == OK else str(err)])
