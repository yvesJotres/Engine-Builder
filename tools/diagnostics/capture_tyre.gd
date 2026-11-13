extends SceneTree

# The tyre on its own, so its section can be judged without the bike around it:
#   1. side elevation      - diameter, sidewall height, bead
#   2. three-quarter       - shoulder roll and crown width
#   3. down the axis       - how round the section is
#   4. cutaway (half)      - the section itself, open, so bead/sidewall/shoulder/crown are legible
# Sizes come from the preset: a 150/60-17 rear is 1.50 units wide on a 3.06 unit radius.
#   godot --path . -s res://tools/diagnostics/capture_tyre.gd [-- <preset>] [-- rear|front]

const OUT_DIR := "res://tools/diagnostics/out"


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

	var rim_r := (spec.front_rim_in if which == "front" else spec.rear_rim_in) * 12.7 * 0.01
	var width_mm := spec.front_tire_width_mm if which == "front" else spec.rear_tire_width_mm
	var aspect := spec.front_tire_aspect if which == "front" else spec.rear_tire_aspect
	var width := width_mm * 0.01
	var outer := rim_r + width * aspect

	var world := Node3D.new()
	root.add_child(world)
	# a neutral clay material: the point of this render is the section's shape, and the tyre's own near-black albedo hides it
	var clay := StandardMaterial3D.new()
	clay.albedo_color = Color(0.52, 0.53, 0.56)
	clay.roughness = 0.82
	var rim_w := BikeTyre.rim_width(width_mm)
	var tyre := BikeTyre.build(outer, width, rim_r, clay, 360.0, rim_w)
	tyre.rotation.z = PI * 0.5 # revolved about Y, unwrap it onto X so the axis is across
	world.add_child(tyre)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.20, 0.21, 0.24)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.80, 0.86)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	world.add_child(world_env)
	var cam := Camera3D.new()
	cam.fov = 30.0
	world.add_child(cam)
	cam.current = true
	for item in [[Vector3(-32, 40, 0), 1.7], [Vector3(20, -138, 14), 0.9], [Vector3(63, 6, -18), 0.45]]:
		var lamp := DirectionalLight3D.new()
		lamp.rotation_degrees = item[0]
		lamp.light_energy = item[1]
		world.add_child(lamp)

	# frame the whole tyre: half the view height at distance d is d*tan(fov/2), so d = radius*1.15/tan(15 deg)
	var span := outer * 4.3
	# warm-up: the first frame after a freshly built mesh can come back empty, which is why the first shot used to save a
	# blank image while every later one was fine
	for i in 8:
		await process_frame
	root.get_texture().get_image()

	var tag := "%s_%s" % [id, which]
	await _shoot(cam, Vector3(-span, 0.12, 0.10), Vector3.ZERO, "%s/tyre_side_%s.png" % [OUT_DIR, tag])
	await _shoot(cam, Vector3(-span * 0.7, span * 0.35, span * 0.55), Vector3.ZERO, "%s/tyre_three_quarter_%s.png" % [OUT_DIR, tag])
	await _shoot(cam, Vector3(span, 0.10, 0.10), Vector3.ZERO, "%s/tyre_axial_%s.png" % [OUT_DIR, tag])

	# the cutaway: half the circumference, so the section is open to the camera
	world.remove_child(tyre)
	var cut := BikeTyre.build(outer, width, rim_r, clay, 180.0, rim_w)
	cut.name = "TyreCut"
	cut.rotation.z = PI * 0.5
	world.add_child(cut)
	await _shoot(cam, Vector3(-span * 0.62, span * 0.16, span * 0.26), Vector3.ZERO, "%s/tyre_cutaway_%s.png" % [OUT_DIR, tag])

	print("tyre %s: %.0f mm wide, %.0f mm diameter, bead radius %.0f mm, sidewall %.0f mm" % [
		which, width * 100.0, outer * 200.0, rim_r * 100.0, (outer - rim_r) * 100.0])
	quit(0)


func _shoot(cam: Camera3D, eye: Vector3, target: Vector3, path: String) -> void:
	cam.global_position = eye
	cam.look_at(target, Vector3.UP)
	for i in 5:
		await process_frame
	var image := root.get_texture().get_image()
	var err := image.save_png(ProjectSettings.globalize_path(path))
	# coverage: a shot with no subject is a bug, not a look, so it is reported rather than saved silently
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
