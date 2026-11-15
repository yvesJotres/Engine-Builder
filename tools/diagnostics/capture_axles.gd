extends SceneTree

# Renders the two axle ends, so the spindle, its nut and the clamp can be seen where they actually are: through the fork
# legs at the front, through the swingarm arms at the back.
# Run windowed (headless has no framebuffer to read the image back):
#   godot --path . -s res://tools/diagnostics/capture_axles.gd [-- <suffix>]

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
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var world := WorldEnvironment.new()
	world.environment = env
	get_root().add_child(world)

	var cam := Camera3D.new()
	cam.fov = 36.0
	get_root().add_child(cam)
	cam.current = true
	for item in [[Vector3(-30.0, 40.0, 0.0), 1.7], [Vector3(15.0, -135.0, 0.0), 0.7]]:
		var lamp := DirectionalLight3D.new()
		lamp.rotation_degrees = item[0]
		lamp.light_energy = item[1]
		get_root().add_child(lamp)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var axles := dt.get_node("Axles")
	for item in [["front", dt._front_wheel.position, "FrontAxle"], ["rear", dt._wheel_pivot.position, "RearAxle"]]:
		var at: Vector3 = item[1]
		var shaft := axles.get_node(item[2]) as MeshInstance3D
		var nut := axles.get_node("%sNut" % item[2]) as Node3D
		# look along the axle from the nut side, a little above and ahead, so the nut, washer and bore are all readable
		var side := signf(nut.position.x)
		var eye := at + Vector3(side * 4.2, 1.1, 1.5)
		await _shoot(cam, eye, at, "%s/axle_%s%s.png" % [OUT_DIR, item[0], suffix])
		print("%s: axle at (%.3f, %.3f, %.3f), nut x %.3f" % [item[0], at.x, at.y, at.z, nut.global_position.x])
	quit(0)


func _shoot(cam: Camera3D, eye: Vector3, target: Vector3, path: String) -> void:
	cam.global_position = eye
	cam.look_at(target, Vector3.UP)
	for i in 3:
		await process_frame
	var image := get_root().get_texture().get_image()
	var err := image.save_png(ProjectSettings.globalize_path(path))
	print("%s: %s" % [path, "saved" if err == OK else str(err)])
