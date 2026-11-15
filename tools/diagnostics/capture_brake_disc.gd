extends SceneTree

# Renders the brake discs on their own, from both faces, so the steel, the drilled holes, the carrier and the ABS sensor
# ring can be looked at without the bike in the way. The ring is on the outboard face of the carrier, so it should appear
# on the outboard view and not on the inboard one.
# Run windowed (headless has no framebuffer to read the image back):
#   godot --path . -s res://tools/diagnostics/capture_brake_disc.gd [-- <suffix>]
# Writes tools/diagnostics/out/disc_{front,rear}_{out,in}<suffix>.png

const OUT_DIR := "res://tools/diagnostics/out"
const PRESET := "honda_cbr1000rrr_sp"


func _init() -> void:
	var suffix := ""
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		suffix = str(args[0])

	var spec := EngineSpec.new()
	var preset: Dictionary = Presets.PRESETS[PRESET]
	for key in preset.keys():
		spec.set(key, preset[key])

	var dt := Drivetrain.new()
	get_root().add_child(dt)
	dt.build(Ground.Y, Vector3.ZERO, Vector3(0.0, 4.0, 0.0), 1.5, spec.abs_hardware(), AABB(), spec, PRESET)
	await process_frame

	# only the disc and its carrier: no tyre, no fork, no caliper
	for child in dt.get_children():
		child.visible = child == dt._front_wheel or child == dt._wheel_pivot
	for wheel in [dt._front_wheel, dt._wheel_pivot]:
		for child in wheel.get_children():
			child.visible = child.name in ["BrakeRotor", "RotorCarrier"]

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.1, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.66, 0.74)
	env.ambient_light_energy = 0.95
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var world := WorldEnvironment.new()
	world.environment = env
	get_root().add_child(world)

	var cam := Camera3D.new()
	cam.fov = 30.0
	get_root().add_child(cam)
	cam.current = true
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38.0, 30.0, 0.0)
	key.light_energy = 1.6
	get_root().add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(12.0, -145.0, 0.0)
	fill.light_energy = 0.7
	get_root().add_child(fill)
	var back := DirectionalLight3D.new()
	back.rotation_degrees = Vector3(25.0, 150.0, 0.0)
	back.light_energy = 0.55
	get_root().add_child(back)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for pair in [["front", dt._front_wheel], ["rear", dt._wheel_pivot]]:
		var wheel: Node3D = pair[1]
		var rotor := wheel.get_node("BrakeRotor") as MeshInstance3D
		var box: AABB = rotor.global_transform * rotor.mesh.get_aabb()
		var centre := box.get_center()
		var span: float = maxf(box.size.y, box.size.z)
		print("%s disc: Ø %.0f mm, %.1f mm thick, centre x %.3f" % [
			pair[0], box.size.y * 100.0, box.size.x * 100.0, centre.x])
		# the wheel is centred on x = 0 and the disc is bolted to one side of it: that side is the outboard one, the
		# side the fork leg and the ABS pickup are on, and the side the sensor ring faces
		var outboard := signf(centre.x) if absf(centre.x) > 0.001 else -1.0
		var ring := wheel.get_node_or_null("RotorCarrier/ABSToneRing") as MeshInstance3D
		print("  sensor ring on the %s face" % ("outboard" if ring != null and signf(ring.global_position.x - centre.x) == outboard else "inboard"))
		await _shoot(cam, centre + Vector3(outboard * span * 1.55, 0.0, 0.0), centre, "%s/disc_%s_outboard%s.png" % [OUT_DIR, pair[0], suffix])
		await _shoot(cam, centre - Vector3(outboard * span * 1.55, 0.0, 0.0), centre, "%s/disc_%s_inboard%s.png" % [OUT_DIR, pair[0], suffix])
	quit(0)


func _shoot(cam: Camera3D, eye: Vector3, target: Vector3, path: String) -> void:
	cam.global_position = eye
	cam.look_at(target, Vector3.UP)
	for i in 3:
		await process_frame
	var image := get_root().get_texture().get_image()
	var err := image.save_png(ProjectSettings.globalize_path(path))
	print("%s: %s" % [path, "saved" if err == OK else str(err)])
