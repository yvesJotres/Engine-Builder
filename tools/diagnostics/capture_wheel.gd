extends SceneTree

# The wheel on its own: tyre and rim, nothing else. Four views -
#   1. side       the face: spokes, barrel lip, the tyre's profile from the outside
#   2. three quarter
#   3. edge       along the wheel's plane: tyre width, bead lips, how the rim sits inside the tyre
#   4. section    the tyre cut in half, so the bead, the sidewall bulge and the rim's drop centre are all visible
#   godot --path . -s res://tools/diagnostics/capture_wheel.gd [-- <preset>] [-- front|rear]

const OUT_DIR := "res://tools/diagnostics/out"

var _key: DirectionalLight3D # a key light that follows the camera, so the tyre's shoulder catches a highlight


func _init() -> void:
	var id := "kawasaki_zx25r"
	var which := "rear"
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if Presets.PRESETS.has(str(arg)):
			id = str(arg)
		elif str(arg) in ["front", "rear"]:
			which = str(arg)
	var spec := EngineSpec.new()
	for key in Presets.PRESETS[id].keys():
		spec.set(key, Presets.PRESETS[id][key])
	var rim_in: float = spec.front_rim_in if which == "front" else spec.rear_rim_in
	var width_mm: int = spec.front_tire_width_mm if which == "front" else spec.rear_tire_width_mm
	var aspect: float = spec.front_tire_aspect if which == "front" else spec.rear_tire_aspect
	var rim_r := rim_in * 12.7 * 0.01 # 17 in bead seat, scene units
	var width := float(width_mm) * 0.01
	var outer := rim_r + width * aspect
	var rim_w := BikeTyre.rim_width(width_mm)
	var hub_r := rim_r * 0.30

	var wheel := Node3D.new()
	root.add_child(wheel)
	var tyre := BikeTyre.build(outer, width, rim_r, Materials.tyre(), 360.0, rim_w)
	tyre.rotation.z = PI * 0.5
	wheel.add_child(tyre)
	var rim := BikeRim.build(rim_r, rim_w, hub_r, Materials.alu(), Materials.dark())
	wheel.add_child(rim)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.22, 0.23, 0.26)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.56, 0.60)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var world := WorldEnvironment.new()
	world.environment = env
	root.add_child(world)
	var cam := Camera3D.new()
	cam.fov = 32.0
	root.add_child(cam)
	cam.current = true
	for item in [[Vector3(-30, 38, 0), 2.0], [Vector3(24, -128, 18), 0.8], [Vector3(62, 8, -20), 0.7]]:
		var lamp := DirectionalLight3D.new()
		lamp.rotation_degrees = item[0]
		lamp.light_energy = item[1]
		root.add_child(lamp)

	_key = DirectionalLight3D.new()
	_key.light_energy = 2.2
	root.add_child(_key)
	for i in 8:
		await process_frame
	root.get_texture().get_image() # warm-up: the first frame after a fresh mesh can come back empty

	# tread numbers, read while the tyre still exists
	var tread_mesh := (tyre.get_node("Tread") as MeshInstance3D).mesh as ArrayMesh
	var tread_verts: PackedVector3Array = tread_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	print("tread: %d pads, %d triangles, %.0f mm of rubber over the carcass" % [
		tread_verts.size() / 32, tread_mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() / 3,
		BikeTyre.TREAD_DEPTH * 100.0])

	var d := outer * 4.2
	var tag := "%s_%s" % [id, which]
	# the whole wheel, five angles. The wheel's axis runs along X, so the face is seen from X, the width from Y.
	await _shoot(cam, Vector3(d * 0.99, d * 0.06, d * 0.10), Vector3.ZERO, "%s/wheel_face_%s.png" % [OUT_DIR, tag])
	await _shoot(cam, Vector3(-d * 0.95, d * 0.14, d * 0.28), Vector3.ZERO, "%s/wheel_back_%s.png" % [OUT_DIR, tag])
	await _shoot(cam, Vector3(-d * 0.58, d * 0.34, d * 0.66), Vector3.ZERO, "%s/wheel_3q_%s.png" % [OUT_DIR, tag])
	await _shoot(cam, Vector3(d * 0.40, d * 0.80, d * 0.28), Vector3.ZERO, "%s/wheel_edge_%s.png" % [OUT_DIR, tag])
	await _shoot(cam, Vector3(d * 0.52, -d * 0.62, d * 0.52), Vector3.ZERO, "%s/wheel_low_%s.png" % [OUT_DIR, tag])
	# the tread, close up: the pattern is the thing being judged, and it cannot be seen from four metres away
	await _shoot(cam, Vector3(outer * 0.35, outer + 0.34, outer * 0.52), Vector3(0.0, outer - 0.06, 0.0),
		"%s/tread_macro_%s.png" % [OUT_DIR, tag])
	await _shoot(cam, Vector3(outer * 0.10, outer + 0.22, outer * 1.30), Vector3(0.0, outer - 0.12, 0.0),
		"%s/tread_graze_%s.png" % [OUT_DIR, tag])
	# a close three-quarter of the tread, roughly the angle and distance the Pirelli product shots are taken from
	var crown := Vector3(0.0, outer, 0.0)
	await _shoot(cam, crown + Vector3(0.62, 0.30, 0.60), crown + Vector3(0.0, -0.06, -0.22),
		"%s/tread_detail_%s.png" % [OUT_DIR, tag])
	# an orthographic look straight down at the crown: the flat "tread pattern" view a tyre photo is taken from, and the
	# only angle where the pattern's shape can actually be judged
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = width * 0.85
	await _shoot(cam, Vector3(0.0, outer + 1.2, 0.0), Vector3(0.0, outer, 0.0), "%s/tread_map_%s.png" % [OUT_DIR, tag])
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE

	# section: the tyre cut in half, the rim whole, so the bead seat and the drop centre show against the tyre's section
	wheel.remove_child(tyre)
	tyre.queue_free()
	var cut := BikeTyre.build(outer, width, rim_r, Materials.tyre(), 270.0, rim_w)
	cut.name = "TyreCut"
	cut.rotation.z = PI * 0.5
	wheel.add_child(cut)
	# three quarters of the tyre, so the missing quarter is a mouth the camera can look into and see the section edge on
	await _shoot(cam, Vector3(d * 0.40, d * 0.74, -d * 0.66), Vector3.ZERO, "%s/wheel_cutaway_%s.png" % [OUT_DIR, tag])
	print("wheel %s: tyre %.1f mm x %.0f mm, rim %.1f mm barrel on a %.1f mm bead seat, %d spokes" % [
		which, width * 100.0, outer * 200.0, rim_w * 100.0, rim_r * 100.0, BikeRim.SPOKES])
	quit(0)


func _shoot(cam: Camera3D, eye: Vector3, target: Vector3, path: String) -> void:
	cam.global_position = eye
	cam.look_at(target, Vector3.UP)
	if _key != null:
		# the key rakes across the surface rather than following the camera dead on, so a step in the tread throws a shadow
		_key.global_position = eye + Vector3(0.0, 0.55, 0.0)
		_key.look_at(target, Vector3.UP)
	for i in 5:
		await process_frame
	var image := root.get_texture().get_image()
	var err := image.save_png(ProjectSettings.globalize_path(path))
	var covered := 0
	var total := 0
	for y in range(0, image.get_height(), 16):
		for x in range(0, image.get_width(), 16):
			total += 1
			var c := image.get_pixel(x, y)
			if (c.r + c.g + c.b) / 3.0 > 0.30:
				covered += 1
	print("%s: %s, subject covers %d%%" % [path.get_file(), "saved" if err == OK else str(err),
		100 * covered / maxi(total, 1)])
