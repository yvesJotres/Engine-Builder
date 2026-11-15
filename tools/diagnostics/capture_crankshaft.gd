extends SceneTree

# Renders the crankshaft on its own, so its proportions can be checked without the engine around it: the nose pulley,
# the main journals, the crank pins with their counterweight lobes, and the flywheel flange with the flywheel.
# Run windowed (a window flashes; headless has no framebuffer to read):
#   godot --path . -s res://tools/diagnostics/capture_crankshaft.gd
# Three views are written to tools/diagnostics/out/: crank_iso.png, crank_side.png, crank_end.png.

const OUT_DIR := "res://tools/diagnostics/out"
const PRESET := "honda_cbr250rr"

func _init() -> void:
	var spec := EngineSpec.new()
	var preset: Dictionary = Presets.PRESETS[PRESET]
	for key in preset.keys():
		spec.set(key, preset[key])

	var model := EngineModel.new()
	get_root().add_child(model)
	model.build(spec)
	# stand the engine up and put it at the origin, so the crank axis is exactly the world x axis in the views below
	model.transform = Transform3D.IDENTITY
	model.update_crank(60.0)
	await process_frame
	var crank := model._crank_node as Crankshaft
	for child in model.get_children():
		child.visible = child == crank

	# the crank sits inside the leaned engine at its real height, so measure and frame it in world space
	var box := crank.global_transform * _aabb(crank)
	print("crank bounds: ", box, "  size mm: ", box.size / Units.M_TO_SCENE * 1000.0)
	print("throws %d, journals %d, counterweights %d, r_cw %.1f mm, web %.1f mm, journal Ø %.1f mm, pin Ø %.1f mm" % [
		crank.throws.size(), crank.journals.size(), crank.counterweights.size(),
		spec.counterweight_radius_m() * 1000.0, spec.counterweight_thickness_m() * 1000.0,
		EngineSpec.MAIN_JOURNAL_RADIUS * 2000.0, EngineSpec.CRANK_PIN_RADIUS * 2000.0])

	# a dark background and a little ambient, so polished steel reads against it
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.09, 0.11)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.7)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var world := WorldEnvironment.new()
	world.environment = env
	get_root().add_child(world)

	var cam := Camera3D.new()
	cam.fov = 40.0
	get_root().add_child(cam)
	cam.current = true
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40.0, 35.0, 0.0)
	light.light_energy = 1.4
	get_root().add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(20.0, -135.0, 0.0)
	fill.light_energy = 0.5
	get_root().add_child(fill)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	# the flywheel is a Ø206 mm disc and it hides everything behind it, so the end and throw views render without it
	var views := [
		{"name": "crank_iso", "dir": Vector3(-1.05, 0.62, 0.85), "flywheel": true,
			"target": box.get_center(), "radius": box.size.length() * 0.42},
		{"name": "crank_side", "dir": Vector3(0.02, 0.10, 1.0), "flywheel": true,
			"target": box.get_center(), "radius": maxf(box.size.x, box.size.y) * 0.58},
		# down the crank axis, flywheel off: the counterweight lobes, the pins and the pulley read against each other
		{"name": "crank_end", "dir": Vector3(-1.0, 0.04, 0.0), "flywheel": false,
			"target": box.get_center(), "radius": box.size.y * 0.38},
		# the crank body alone, flywheel off: every web, pin and journal in one frame
		{"name": "crank_body", "dir": Vector3(-0.8, 0.55, 0.85), "flywheel": false,
			"target": box.get_center(), "radius": box.size.x * 0.40},
		# one throw, close up: web, crank pin, web between two main journals
		{"name": "crank_throw", "dir": Vector3(-0.45, 0.35, 1.0), "flywheel": false,
			"target": crank.global_transform * Vector3(crank.throws[0].position.x, 0.0, 0.0), "radius": 0.95},
	]
	for view in views:
		crank.flywheel.visible = view["flywheel"]
		var target: Vector3 = view["target"]
		var radius: float = view["radius"]
		var dir := (view["dir"] as Vector3).normalized()
		var dist := radius / tan(deg_to_rad(cam.fov * 0.5))
		cam.look_at_from_position(target + dir * dist, target, Vector3.UP if absf(dir.y) < 0.95 else Vector3.FORWARD)
		print("%s: camera %s -> target %s, radius %.2f" % [view["name"], cam.global_position, target, radius])
		for i in 4:
			await process_frame
		var image := get_root().get_texture().get_image()
		var path := ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, view["name"]])
		image.save_png(path)
		print("saved ", path)
	quit(0)


# Bounding box of every mesh under a node, in that node's own space.
func _aabb(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in _meshes(node):
		var local := Transform3D.IDENTITY
		var n: Node = mi
		while n != node:
			local = (n as Node3D).transform * local
			n = n.get_parent()
		var b: AABB = local * (mi.mesh as Mesh).get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for child in node.get_children():
		if child is MeshInstance3D:
			out.append(child)
		out.append_array(_meshes(child))
	return out
