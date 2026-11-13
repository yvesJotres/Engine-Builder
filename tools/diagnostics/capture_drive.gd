extends SceneTree

# Renders the drive: the rear sprocket on its carrier with the chain wrapping it, the countershaft sprocket, and the chain
# runs in between.
#   godot --path . -s res://tools/diagnostics/capture_drive.gd [-- <preset>]

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
	var bike := Drivetrain.new()
	bike.name = "Bike"
	root.add_child(bike)
	bike.build(Ground.Y, Vector3(0.0, 0.9, -0.5), Vector3(0.0, 4.0, -1.0), 1.1, true, AABB(), spec, id)
	await process_frame

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.1, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.74, 0.77, 0.84)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var world := WorldEnvironment.new()
	world.environment = env
	root.add_child(world)
	var cam := Camera3D.new()
	cam.fov = 32.0
	root.add_child(cam)
	cam.current = true
	for item in [[Vector3(-28, 42, 0), 2.0], [Vector3(26, -140, 12), 0.9], [Vector3(60, 10, -25), 0.5]]:
		var lamp := DirectionalLight3D.new()
		lamp.rotation_degrees = item[0]
		lamp.light_energy = item[1]
		root.add_child(lamp)

	var rear: Vector3 = bike.rear_axle
	# 1. the rear sprocket and its carrier, from outboard
	await _shoot(cam, rear + Vector3(-3.2, 1.1, 1.6), rear, "%s/drive_rear%s.png" % [OUT_DIR, suffix])
	# 2. the countershaft sprocket
	var front: Vector3 = bike.get_node("FrontSprocketPivot").position
	await _shoot(cam, front + Vector3(-1.6, 0.5, 1.2), front, "%s/drive_front%s.png" % [OUT_DIR, suffix])
	# 2b. the wheel itself: section, spokes, bead
	await _shoot(cam, rear + Vector3(-2.6, 0.9, 0.9), rear, "%s/wheel_side%s.png" % [OUT_DIR, suffix])
	await _shoot(cam, rear + Vector3(1.4, 1.3, -2.2), rear + Vector3(0.0, 0.0, 0.2), "%s/wheel_angle%s.png" % [OUT_DIR, suffix])
	# 3. a link close-up on the top run: the plate shape is the thing being judged
	var top := rear.lerp(front, 0.55) + Vector3(0.0, Drivetrain.sprocket_radius(Drivetrain.TEETH_REAR) * 0.75, 0.0)
	await _shoot(cam, top + Vector3(-1.4, 0.55, 0.85), top, "%s/drive_links%s.png" % [OUT_DIR, suffix])
	# 4. the whole run, so the chain's two sides read
	var middle: Vector3 = (rear + front) * 0.5
	await _shoot(cam, middle + Vector3(-6.0, 2.0, 4.0), middle, "%s/drive_run%s.png" % [OUT_DIR, suffix])
	print("drive: %dT front, %dT rear, %d links" % [Drivetrain.TEETH_FRONT, Drivetrain.TEETH_REAR, Drivetrain.CHAIN_LINKS])
	quit(0)


func _shoot(cam: Camera3D, eye: Vector3, target: Vector3, path: String) -> void:
	cam.global_position = eye
	cam.look_at(target, Vector3.UP)
	for i in 3:
		await process_frame
	var image := root.get_texture().get_image()
	var err := image.save_png(ProjectSettings.globalize_path(path))
	print("%s: %s" % [path, "saved" if err == OK else str(err)])
