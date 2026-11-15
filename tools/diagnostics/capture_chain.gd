extends SceneTree

# Five links of the drive chain on their own: plan, elevation and isometric. Built from the same parts the bike uses, laid
# out straight, so the anatomy can be inspected without a sprocket in the way.
#   godot --path . -s res://tools/diagnostics/capture_chain.gd

const OUT := "res://tools/diagnostics/out"
const JOINTS := 5


func _init() -> void:
	var pitch: float = Drivetrain.CHAIN_PITCH
	var roller_r: float = Drivetrain.ROLLER_RADIUS
	var inner_t: float = Drivetrain.INNER_PLATE_T
	var outer_t: float = Drivetrain.OUTER_PLATE_T
	var end_r: float = Drivetrain.PLATE_END_RADIUS
	var waist_r: float = Drivetrain.PLATE_WAIST_RADIUS
	var plate_off: float = Drivetrain.PLATE_OFFSET
	var outer_x: float = Drivetrain.OUTER_PLATE_X
	var chain_out: float = Drivetrain.CHAIN_OUTER_FACE
	var steel := Materials.steel()
	var alu := Materials.alu()
	var dark := Materials.dark()
	var inner_plate := ChainLink.plate_mesh(pitch, inner_t, end_r, waist_r)
	var outer_plate := ChainLink.plate_mesh(pitch, outer_t, end_r, waist_r)

	var chain := Node3D.new()
	chain.name = "Chain"
	root.add_child(chain)
	for k in JOINTS:
		var joint := Vector3(0.0, 0.0, pitch * float(k))
		var inner_joint: bool = (k % 2) == 0
		# the roller, running on the bushing
		var roller := CylinderMesh.new()
		roller.top_radius = roller_r
		roller.bottom_radius = roller_r
		roller.height = Drivetrain.ROLLER_LENGTH_SHORT
		roller.radial_segments = 16
		_part(chain, roller, alu, joint, true)
		# the bushing, longer than the roller so its ends show
		var bushing := CylinderMesh.new()
		bushing.top_radius = Drivetrain.PIN_RADIUS * 1.35
		bushing.bottom_radius = Drivetrain.PIN_RADIUS * 1.35
		bushing.height = Drivetrain.BUSHING_LENGTH
		bushing.radial_segments = 14
		_part(chain, bushing, steel, joint, true)
		# the pin, through everything
		var pin := CylinderMesh.new()
		pin.top_radius = Drivetrain.PIN_RADIUS
		pin.bottom_radius = Drivetrain.PIN_RADIUS
		pin.height = Drivetrain.PIN_HALF * 2.0
		pin.radial_segments = 10
		_part(chain, pin, steel, joint, true)
		for side in [-1.0, 1.0]:
			if inner_joint:
				_part(chain, inner_plate, dark, joint + Vector3(side * plate_off, 0.0, 0.0), false)
			else:
				_part(chain, outer_plate, dark, joint + Vector3(side * outer_x, 0.0, 0.0), false)
				var washer := ChainLink.pin_boss_mesh(roller_r, Drivetrain.PLATE_THICKNESS * 0.35)
				_part(chain, washer, steel, joint + Vector3(side * (chain_out + 0.004), 0.0, 0.0), true)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.26, 0.27, 0.30)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.74, 0.80)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var world := WorldEnvironment.new()
	world.environment = env
	root.add_child(world)
	var cam := Camera3D.new()
	cam.fov = 28.0
	root.add_child(cam)
	cam.current = true
	for item in [[Vector3(-34, 46, -18), 2.1], [Vector3(30, -120, 24), 0.7], [Vector3(52, 12, 30), 0.9]]:
		var lamp := DirectionalLight3D.new()
		lamp.rotation_degrees = item[0]
		lamp.light_energy = item[1]
		root.add_child(lamp)

	for i in 8:
		await process_frame
	root.get_texture().get_image() # warm-up

	var middle := Vector3(0.0, 0.0, pitch * float(JOINTS - 1) * 0.5)
	var length: float = pitch * float(JOINTS - 1)
	# Godot's orthographic size is the *vertical* extent, and the frame is 16:9, so the chain's length decides it
	var span: float = length / 1.55
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = span
	await _shoot(cam, middle + Vector3(0.0, 2.0, 0.0), middle, Vector3(0.0, 0.0, -1.0),
		"%s/chain_top.png" % OUT)
	await _shoot(cam, middle + Vector3(2.0, 0.0, 0.0), middle, Vector3(0.0, 1.0, 0.0),
		"%s/chain_side.png" % OUT)
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	var d: float = length * 1.35
	await _shoot(cam, middle + Vector3(d * 0.62, d * 0.45, d * 0.62), middle, Vector3(0.0, 1.0, 0.0),
		"%s/chain_iso.png" % OUT)
	print("chain: pitch %.3f mm, roller Ø%.2f, pin Ø%.2f, roller width %.2f, plate end r %.2f, waist r %.2f, outer face %.2f" % [
		pitch * 100.0, roller_r * 200.0, Drivetrain.PIN_RADIUS * 200.0, Drivetrain.ROLLER_WIDTH * 100.0,
		end_r * 100.0, waist_r * 100.0, chain_out * 100.0])
	quit(0)


func _part(parent: Node3D, mesh: Mesh, mat: Material, at: Vector3, along_x: bool) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	if along_x:
		mi.rotation.z = PI * 0.5 # cylinders are built along Y; the chain's pins run along X
	mi.position = at
	parent.add_child(mi)


func _shoot(cam: Camera3D, eye: Vector3, target: Vector3, up: Vector3, path: String) -> void:
	cam.global_position = eye
	cam.look_at(target, up)
	for i in 5:
		await process_frame
	var image := root.get_texture().get_image()
	var err := image.save_png(ProjectSettings.globalize_path(path))
	var lit := 0
	var total := 0
	for y in range(0, image.get_height(), 16):
		for x in range(0, image.get_width(), 16):
			total += 1
			var c := image.get_pixel(x, y)
			if (c.r + c.g + c.b) / 3.0 > 0.36:
				lit += 1
	print("%s: %s, subject covers %d%%" % [path.get_file(), "saved" if err == OK else str(err),
		100 * lit / maxi(total, 1)])
