extends SceneTree

# Renders the header on its own: the primaries and the flanges that bolt them to the head, then the same run with the engine
# behind it so the port to pipe to collector path is readable.
# Run windowed (headless has no framebuffer):
#   godot --path . -s res://tools/diagnostics/capture_header.gd [-- <preset>]

const OUT_DIR := "res://tools/diagnostics/out"


func _init() -> void:
	var id := "honda_cbr1000rrr_sp"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and Presets.PRESETS.has(str(args[0])):
		id = str(args[0])
	var suffix := "" if id == "honda_cbr1000rrr_sp" else "_" + id

	var spec := EngineSpec.new()
	for key in Presets.PRESETS[id].keys():
		spec.set(key, Presets.PRESETS[id][key])
	var model := EngineModel.new()
	model.name = "Engine"
	root.add_child(model)
	model.build(spec)

	var layout := ExhaustLayout.build(spec, model.exhaust_ports(), model.crank_position(), Ground.Y,
		Vector3(0.0, 3.0, -5.95))
	var exhaust := Exhaust.new()
	exhaust.name = "Exhaust"
	root.add_child(exhaust)
	exhaust.build(layout, null)
	await process_frame

	# keep the primaries, their bores and their flanges; hide the rest of the system
	for child in exhaust.get_children():
		var keep := false
		for prefix in ["Pipe_primary", "Flange_"]:
			if str(child.name).begins_with(prefix):
				keep = true
		child.visible = keep
	model.visible = false

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.1, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.75, 0.82)
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var world := WorldEnvironment.new()
	world.environment = env
	root.add_child(world)
	var cam := Camera3D.new()
	cam.fov = 34.0
	root.add_child(cam)
	cam.current = true
	for item in [[Vector3(-32, 42, 0), 1.9], [Vector3(24, -135, 10), 0.8], [Vector3(70, 8, -20), 0.5]]:
		var lamp := DirectionalLight3D.new()
		lamp.rotation_degrees = item[0]
		lamp.light_energy = item[1]
		root.add_child(lamp)

	# frame the header from its own bounds rather than from fixed numbers, so this works on any engine
	var ports: Array = model.exhaust_ports()
	var centre := Vector3.ZERO
	for p in ports:
		centre += p
	centre /= maxf(1.0, float(ports.size()))
	var prim_end := centre
	for pipe in layout.pipes:
		if pipe.kind == "collector":
			prim_end = pipe.pts[0]
	var span: float = centre.distance_to(prim_end) + 1.2
	var mid := centre.lerp(prim_end, 0.45)

	await _shoot(cam, mid + Vector3(-span * 1.5, span * 0.75, span * 1.2), mid, "%s/header_ports%s.png" % [OUT_DIR, suffix])
	await _shoot(cam, mid + Vector3(-span * 2.0, span * 0.25, 0.0), mid, "%s/header_side%s.png" % [OUT_DIR, suffix])
	model.visible = true
	await _shoot(cam, mid + Vector3(-span * 1.8, span * 0.9, span * 1.3), mid, "%s/header_engine%s.png" % [OUT_DIR, suffix])
	print("header: %d primaries, %.0f mm tube, %d flanges" % [
		_model_cylinders(spec), _primary_mm(layout), _count(exhaust, "Flange_")])
	quit(0)


func _shoot(cam: Camera3D, eye: Vector3, target: Vector3, path: String) -> void:
	cam.global_position = eye
	cam.look_at(target, Vector3.UP)
	for i in 3:
		await process_frame
	var image := root.get_texture().get_image()
	var err := image.save_png(ProjectSettings.globalize_path(path))
	print("%s: %s" % [path, "saved" if err == OK else str(err)])


func _model_cylinders(spec: EngineSpec) -> int:
	return spec.cylinders


func _primary_mm(layout: ExhaustLayout) -> float:
	for pipe in layout.pipes:
		if pipe.kind == "primary":
			return pipe.radii[0] * 200.0
	return 0.0


func _count(node: Node, prefix: String) -> int:
	var total := 0
	for child in node.get_children():
		if str(child.name).begins_with(prefix):
			total += 1
	return total
