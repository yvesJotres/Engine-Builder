extends SceneTree

# Renders the brake system in place: the pair of front discs with their radial calipers on the fork legs, and the rear
# caliper on its bracket. The discs and calipers are what changed, so this is framed on them, with the wheel and fork
# left visible for scale.
# Run windowed (headless has no framebuffer to read the image back):
#   godot --path . -s res://tools/diagnostics/capture_brakes.gd [-- <suffix>]

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
	cam.fov = 34.0
	get_root().add_child(cam)
	cam.current = true
	for item in [[Vector3(-40.0, 35.0, 0.0), 1.7], [Vector3(10.0, -140.0, 0.0), 0.7]]:
		var lamp := DirectionalLight3D.new()
		lamp.rotation_degrees = item[0]
		lamp.light_energy = item[1]
		get_root().add_child(lamp)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var brakes := dt.get_node("BrakeHardware")
	# front: the whole disc with its caliper, from outboard and slightly ahead
	var front_caliper := brakes.get_node("FrontCaliper") as Node3D
	var front_disc := dt._front_wheel.get_node("BrakeRotor") as MeshInstance3D
	var front_box: AABB = front_disc.global_transform * front_disc.mesh.get_aabb()
	var front_centre := front_box.get_center()
	var span: float = maxf(front_box.size.y, front_box.size.z)
	await _shoot(cam, front_centre + Vector3(-span * 1.5, span * 0.75, span * 0.85), front_centre,
		"%s/brakes_front%s.png" % [OUT_DIR, suffix])
	print("front: disc Ø %.0f mm, caliper at %.0f mm radius" % [
		front_box.size.y * 100.0,
		Vector2(front_caliper.global_position.y - dt._front_wheel.global_position.y,
			front_caliper.global_position.z - dt._front_wheel.global_position.z).length() * 100.0])

	# rear: the caliper, its bracket and the torque arm
	var rear_caliper := brakes.get_node("RearCaliper") as Node3D
	var rear_disc := dt._wheel_pivot.get_node("BrakeRotor") as MeshInstance3D
	var rear_box: AABB = rear_disc.global_transform * rear_disc.mesh.get_aabb()
	var rear_centre := rear_box.get_center()
	var rear_span: float = maxf(rear_box.size.y, rear_box.size.z)
	await _shoot(cam, rear_centre + Vector3(-rear_span * 1.9, rear_span * 0.9, rear_span * 0.7), rear_centre,
		"%s/brakes_rear%s.png" % [OUT_DIR, suffix])
	print("rear : disc Ø %.0f mm, caliper at %.0f mm radius" % [
		rear_box.size.y * 100.0,
		Vector2(rear_caliper.global_position.y - dt._wheel_pivot.global_position.y,
			rear_caliper.global_position.z - dt._wheel_pivot.global_position.z).length() * 100.0])
	quit(0)


func _shoot(cam: Camera3D, eye: Vector3, target: Vector3, path: String) -> void:
	cam.global_position = eye
	cam.look_at(target, Vector3.UP)
	for i in 3:
		await process_frame
	var image := get_root().get_texture().get_image()
	var err := image.save_png(ProjectSettings.globalize_path(path))
	print("%s: %s" % [path, "saved" if err == OK else str(err)])
