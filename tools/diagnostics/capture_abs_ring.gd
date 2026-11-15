extends SceneTree

# Renders the ABS sensor ring on its own, so its face can be looked at rather than guessed at. A real ring of the flat
# axial style is a steel annulus with a row of rectangular windows punched round it; if it renders as points or lobes
# instead of slots, that shows up here in a second.
# Run windowed (headless has no framebuffer to read the image back):
#   godot --path . -s res://tools/diagnostics/capture_abs_ring.gd -- <suffix>
# Writes tools/diagnostics/out/abs_ring_face<suffix>.png and abs_ring_angle<suffix>.png.

const OUT_DIR := "res://tools/diagnostics/out"
const PRESET := "honda_cbr1000rrr_sp"


func _init() -> void:
	var suffix := "before"
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

	# keep the front wheel and its disc only
	for child in dt.get_children():
		child.visible = child == dt._front_wheel
	for child in dt._front_wheel.get_children():
		child.visible = child.name in ["BrakeRotor", "RotorCarrier"]
	var carrier := dt._front_wheel.get_node("RotorCarrier") as Node3D
	var ring := carrier.get_node_or_null("ABSToneRing") as MeshInstance3D
	print("ring found: %s" % (ring != null))
	if ring == null:
		quit(1)
		return
	if suffix == "before":
		# the ring as it was drawn before the windows were punched: teeth zig-zagged on the outer edge of a solid face
		ring.mesh = _star_ring(0.374, 0.66, Drivetrain.TONE_RING_THICKNESS, Drivetrain.TONE_RING_TEETH)
	var box: AABB = ring.global_transform * ring.mesh.get_aabb()
	print("ring bounds: ", box, "  outer Ø %.0f mm, thickness %.1f mm" % [box.size.y * 200.0, box.size.x * 100.0])

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.1, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.64, 0.72)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var world := WorldEnvironment.new()
	world.environment = env
	get_root().add_child(world)

	var cam := Camera3D.new()
	cam.fov = 32.0
	get_root().add_child(cam)
	cam.current = true
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38.0, 30.0, 0.0)
	key.light_energy = 1.5
	get_root().add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(15.0, -140.0, 0.0)
	fill.light_energy = 0.6
	get_root().add_child(fill)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var centre := box.get_center()
	var span: float = maxf(box.size.y, box.size.z)
	# outboard is -x: the ring sits on the carrier face the pickup looks at
	var face_pos := centre + Vector3(-span * 1.9, 0.0, 0.0)
	await _shoot(cam, face_pos, centre, "%s/abs_ring_face%s.png" % [OUT_DIR, suffix])
	var angle_pos := centre + Vector3(-span * 1.15, span * 0.70, span * 0.95)
	await _shoot(cam, angle_pos, centre, "%s/abs_ring_angle%s.png" % [OUT_DIR, suffix])
	quit(0)


# The previous ring: one solid disc whose outer edge zig-zags between the full radius and three quarters of it. Kept only
# so the diagnostics can render the before/after pair - a star silhouette with no holes in the face.
func _star_ring(inner: float, outer: float, thickness: float, teeth: int) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := teeth * 2
	var half := thickness * 0.5
	var angles := PackedFloat32Array()
	var radii := PackedFloat32Array()
	for i in sides + 1:
		angles.append(TAU * float(i) / float(sides))
		radii.append(outer if i % 2 == 0 else lerpf(inner, outer, 0.72))
	for i in sides:
		var a := angles[i]
		var b := angles[i + 1]
		var ra := radii[i]
		var rb := radii[i + 1]
		var na := Vector3(0.0, cos(a), sin(a))
		var nb := Vector3(0.0, cos(b), sin(b))
		for side in [-1.0, 1.0]:
			var x: float = side * half
			var p := Vector3(x, inner * cos(a), inner * sin(a))
			var q := Vector3(x, ra * cos(a), ra * sin(a))
			var s := Vector3(x, inner * cos(b), inner * sin(b))
			var t := Vector3(x, rb * cos(b), rb * sin(b))
			for v in [p, q, s, s, q, t]:
				surface.set_normal(Vector3(side, 0.0, 0.0))
				surface.add_vertex(v)
		for item in [[Vector3(-half, ra * cos(a), ra * sin(a)), na], [Vector3(half, ra * cos(a), ra * sin(a)), na],
				[Vector3(-half, rb * cos(b), rb * sin(b)), nb], [Vector3(-half, rb * cos(b), rb * sin(b)), nb],
				[Vector3(half, ra * cos(a), ra * sin(a)), na], [Vector3(half, rb * cos(b), rb * sin(b)), nb]]:
			surface.set_normal(item[1])
			surface.add_vertex(item[0])
		for item in [[Vector3(-half, inner * cos(a), inner * sin(a)), -na], [Vector3(half, inner * cos(a), inner * sin(a)), -na],
				[Vector3(-half, inner * cos(b), inner * sin(b)), -nb], [Vector3(-half, inner * cos(b), inner * sin(b)), -nb],
				[Vector3(half, inner * cos(a), inner * sin(a)), -na], [Vector3(half, inner * cos(b), inner * sin(b)), -nb]]:
			surface.set_normal(item[1])
			surface.add_vertex(item[0])
	return surface.commit()


func _shoot(cam: Camera3D, eye: Vector3, target: Vector3, path: String) -> void:
	cam.global_position = eye
	cam.look_at(target, Vector3.UP)
	for i in 3:
		await process_frame
	var image := get_root().get_texture().get_image()
	var err := image.save_png(ProjectSettings.globalize_path(path))
	print("%s: %s (%dx%d)" % [path, "saved" if err == OK else str(err), image.get_width(), image.get_height()])
