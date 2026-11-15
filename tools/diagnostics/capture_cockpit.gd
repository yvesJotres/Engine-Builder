extends SceneTree

# Renders the steering head and proves each control is actually on screen: every part is projected through the camera and
# the pixel under it is sampled, so a render that misses the bars cannot be mistaken for bars that are not there.
# Run windowed (headless has no framebuffer to read the image back):
#   godot --path . -s res://tools/diagnostics/capture_cockpit.gd [-- <suffix>]

const OUT_DIR := "res://tools/diagnostics/out"
const PRESET := "honda_cbr1000rrr_sp"
const PARTS := ["Cockpit/TopYoke", "Cockpit/ForkClampTopLeft", "Cockpit/ForkClampTopLeft/Boss",
	"Cockpit/ForkClampTopLeft/PinchBolt0", "Cockpit/ForkClampBottomRight", "Cockpit/ClipOnLeft", "Cockpit/ClipOnRight", "Cockpit/ThrottleGrip/ThrottleTube/Grip",
	"Cockpit/Grip", "Cockpit/FrontBrakeLever", "Cockpit/ClutchLever", "BrakeHardware/FrontMasterCylinder",
	"BrakeHardware/FrontMasterClamp", "BrakeHardware/FrontMasterBanjo", "BrakeHardware/FrontReservoir",
	"BrakeHardware/FrontReservoirBracket"]


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
	# pull the brake and the throttle in, so the lever and the twist grip are not sitting at rest
	dt.update(0.0, 60.0, 1.0 / 60.0, 1.0, 1.0, 0.0)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.1, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.66, 0.74)
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var world := WorldEnvironment.new()
	world.environment = env
	get_root().add_child(world)

	var cam := Camera3D.new()
	cam.fov = 42.0
	get_root().add_child(cam)
	cam.current = true
	for item in [[Vector3(-35.0, 35.0, 0.0), 1.8], [Vector3(20.0, -140.0, 0.0), 0.8], [Vector3(60.0, 10.0, 0.0), 0.5]]:
		var lamp := DirectionalLight3D.new()
		lamp.rotation_degrees = item[0]
		lamp.light_energy = item[1]
		get_root().add_child(lamp)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var yoke: Vector3 = (dt.get_node("Cockpit/TopYoke") as Node3D).global_position
	var grips: Vector3 = ((dt.get_node("Cockpit/Grip") as Node3D).global_position
		+ (dt.get_node("Cockpit/ThrottleGrip") as Node3D).global_position) * 0.5
	var centre := (yoke + grips) * 0.5
	# a three-quarter view from the rider's side with the whole steering head in frame
	await _shoot(cam, dt, centre + Vector3(6.5, 5.0, 7.5), centre, "%s/cockpit_above%s.png" % [OUT_DIR, suffix])
	# from where the rider's head is, looking forward over the bars
	await _shoot(cam, dt, grips + Vector3(0.0, 1.7, -2.8), grips + Vector3(0.0, 0.10, 2.2),
		"%s/cockpit_rider%s.png" % [OUT_DIR, suffix])
	# and the whole bike, so the bars are seen in proportion and not only in close-up
	await _shoot(cam, dt, Vector3(16.0, 12.0, 26.0), Vector3(0.0, 3.0, 1.0), "%s/cockpit_bike%s.png" % [OUT_DIR, suffix])
	print("brake lever %.0f deg in, throttle %.0f deg round" % [
		rad_to_deg(dt._brake_lever.rotation.y), rad_to_deg(dt._throttle_grip.rotation.y)])
	quit(0)


func _shoot(cam: Camera3D, dt: Node3D, eye: Vector3, target: Vector3, path: String) -> void:
	cam.global_position = eye
	cam.look_at(target, Vector3.UP)
	for i in 3:
		await process_frame
	var image := get_root().get_texture().get_image()
	var err := image.save_png(ProjectSettings.globalize_path(path))
	print("%s: %s" % [path, "saved" if err == OK else str(err)])
	if not path.contains("bike"):
		_report(cam, dt, image)


# Where each control lands in this frame, and whether anything is drawn there.
func _report(cam: Camera3D, dt: Node3D, image: Image) -> void:
	var size := Vector2(image.get_width(), image.get_height())
	for part in PARTS:
		var node := dt.get_node_or_null(part) as Node3D
		if node == null:
			print("  %-42s MISSING" % part)
			continue
		var screen: Vector2 = cam.unproject_position(node.global_position)
		if screen.x < 0.0 or screen.y < 0.0 or screen.x >= size.x or screen.y >= size.y:
			print("  %-42s off screen at (%.0f, %.0f)" % [part, screen.x, screen.y])
			continue
		var pixel := image.get_pixel(int(screen.x), int(screen.y))
		var luma := 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b
		print("  %-42s at (%.0f, %.0f)  luma %.2f %s" % [part, screen.x, screen.y, luma,
			"(background)" if luma < 0.13 else "(drawn)"])
