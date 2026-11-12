class_name Drivetrain
extends Node3D

# Drive side of the bike: 15T front sprocket on the crank, chain, 45T rear sprocket on the
# 130/70-17 rear wheel. Scene units follow EngineModel: 1 unit = 10 cm.

const MM := Units.MM_TO_SCENE
const CHAIN_PITCH := 12.7 * MM # 428 chain, 1/2 inch pitch
const CHAIN_LINKS := 128 # K45R drive chain RK428HSEI-128J, fixed length, so the rear axle position sets the tension
const TEETH_FRONT := 15
const TEETH_REAR := 45
const FINAL_DRIVE := 45.0 / 15.0 # rear wheel turns this many times per front sprocket turn
const RIM_DIAMETER_MM := 17.0 * 25.4
const TIRE_WIDTH_MM := 130.0
const TIRE_ASPECT := 0.70 # sidewall height is 70% of the tyre width
const WHEELBASE := 1310.0 * MM # 1310 mm, Honda CBR150R spec, front axle to rear axle
const CHAIN_X := 0.9 # chain plane, right side of the bike, outboard of the tyre (half width 0.65) and the flywheel
const PLATE_OFFSET := 0.045 # scene units, side plates sit this far either side of the chain centre (inner width about 7.8 mm)
const PLATE_THICKNESS := 0.012 # 1.2 mm plate
const PLATE_HEIGHT := 0.075 # 7.5 mm plate height
const ROLLER_RADIUS := 0.0388 # 7.75 mm roller diameter
const ROLLER_LENGTH := 0.078 # between the plates
const ROLLER_TURN := Basis(Vector3.BACK, PI / 2.0) # turns the cylinder's axis from Y to X
const ROTOR_THICKNESS := BikeMeshes.ROTOR_THICKNESS
const ROTOR_INNER := BikeMeshes.ROTOR_INNER
# The ABS target ring, from how the real part works: a steel disc with teeth round its circumference bolted to the
# carrier, one pulse per tooth per revolution, read by a pickup whose tip sits over the toothed band with a small air gap.
# Bosch/aftermarket reluctor rings run 44-52 teeth (48 is the common figure, and 48 pulses/rev is what a 250 mm disc at
# 100 km/h needs for the module to resolve low speed); the air gap is 0.4-1.2 mm for a passive (inductive) sensor and
# 0.5-2.0 mm for an active/Hall one, with workshop specs landing around 1.3-1.9 mm on some bikes and 0.1-1.5 mm on
# others. The ring itself is 1.5-2.5 mm of steel; ours is 2 mm.
# Real brake sizes, not guesses: a litre-class sport bike runs 330 mm twin front discs with radial four-piston
# calipers and a 220 mm rear (CBR1000RR-R: "330 mm discs paired with radial-mount Brembo Stylema calipers").
const FRONT_DISC_RADIUS := BikeBrakes.FRONT_DISC_RADIUS
const REAR_DISC_RADIUS := BikeBrakes.REAR_DISC_RADIUS
const CALIPER_ANGLE_DEG := BikeBrakes.CALIPER_ANGLE_DEG
const FORK_LEG_OFFSET := BikeChassis.FORK_LEG_OFFSET
const SWINGARM_AXLE_OFFSET := BikeChassis.SWINGARM_AXLE_OFFSET
const AXLE_FRONT_RADIUS := BikeAxles.AXLE_FRONT_RADIUS
const AXLE_REAR_RADIUS := BikeAxles.AXLE_REAR_RADIUS
const TONE_RING_THICKNESS := BikeBrakes.TONE_RING_THICKNESS
const TONE_RING_TEETH := BikeBrakes.TONE_RING_TEETH
const TONE_RING_INNER := BikeBrakes.TONE_RING_INNER
const TONE_RING_OUTER := BikeBrakes.TONE_RING_OUTER
const TONE_RING_WINDOW_LO := BikeMeshes.TONE_RING_WINDOW_LO
const TONE_RING_WINDOW_HI := BikeMeshes.TONE_RING_WINDOW_HI
const TONE_RING_DUTY := BikeMeshes.TONE_RING_DUTY
# Radius a wheel-speed pickup reads at: the middle of the window band, where a real pole piece sits.
const TONE_RING_READ_SHARE := BikeBrakes.TONE_RING_READ_SHARE
const CARRIER_THICKNESS := BikeBrakes.CARRIER_THICKNESS
const CARRIER_OFFSET := BikeBrakes.CARRIER_OFFSET

var _front_pivot: Node3D
var _wheel_pivot: Node3D
var _front_wheel: Node3D
var _wheel_angle := 0.0
var _path := PackedVector2Array() # chain loop, (y, z) points
var _path_cum := PackedFloat32Array() # cumulative length along the loop
var _path_total := 0.0
var _links: MultiMesh # side plates, two per link
var _rollers: MultiMesh
var _clip: MultiMesh # master link clip
var _chain_offset := 0.0 # how far the chain has travelled, along the loop
var _rear_radius := 0.0
var _rear_tire_radius := 0.0
var _front_tire_radius := 0.0
var _chain_x := CHAIN_X
var front_axle := Vector3.ZERO
var _front_half := 0.5
var _rear_half := 0.65
var rear_axle := Vector3.ZERO # rear axle centre, set by build
var _brake_pedal: Node3D
var _shift_pedal: Node3D
var _head := Vector3.ZERO # steering head, set by _build_chassis: where the bars, the fork and the throttle hang
var _brake_lever: Node3D # front brake lever, swings in as the lever is pulled
var _clutch_lever: Node3D
var _throttle_grip: Node3D # the right-hand grip and its tube, which twists
# Clip-on and lever sizes, in scene units (1 unit = 100 mm): a clip-on tube runs about 320 mm from the fork clamp out to
# the end of the grip, the grip itself is 120 mm of rubber, and a lever is about 170 mm from its pivot to the tip.
# A clip-on clamps to the fork tube and runs OUT and back from it: the grips end up wider than the tubes, because a bike's
# bars are about 720 mm across while its fork legs are 160 mm apart. Splaying them inwards put both grips in the middle of
# the machine.
const BAR_END_X := BikeCockpit.BAR_END_X
const BAR_END_Z := BikeCockpit.BAR_END_Z
const BAR_RADIUS := BikeCockpit.BAR_RADIUS
const GRIP_LENGTH := BikeCockpit.GRIP_LENGTH
const GRIP_RADIUS := BikeCockpit.GRIP_RADIUS
const LEVER_LENGTH := BikeCockpit.LEVER_LENGTH
const LEVER_PIVOT_OFFSET := BikeCockpit.LEVER_PIVOT_OFFSET
const LEVER_TRAVEL := 0.34 # rad the brake and clutch levers swing when pulled right in (~19 degrees)
const THROTTLE_TWIST := 0.30 # rad a quarter-turn twist grip moves through
const SHIFT_PEDAL_ANGLE := 0.26
const SHIFT_PEDAL_RETURN_RATE := 2.0


# Where the throttle housing sits: the right-hand bar end. The grip turns a tube that hits a mechanical stop, so the
# clank is a sound at the bar, not at the exhaust: 15 cm inboard of the 1.3-unit tube end, the same axis as the brake
# master cylinder on the other side.
func throttle_housing_position() -> Vector3:
	return to_global(_head + Vector3(1.15, 0.66, -0.16))


# Outer radius of the 100/80-17 front tyre, scene units: rim radius plus an 80 mm sidewall (80% of 100 mm).
static func front_tire_outer_radius() -> float:
	return (RIM_DIAMETER_MM * 0.5 + 100.0 * 0.80) * MM


# One wheel: tyre, rim, spokes and hub, centred on the pivot.
func _add_tyre(pivot: Node3D, tire_r: float, tire_width: float, black: Material, alu: Material, dark: Material, rim_radius: float = RIM_DIAMETER_MM * 0.5 * MM, rim_scene: PackedScene = null) -> void:
	var tire := MeshInstance3D.new()
	tire.name = "Tyre"
	var torus := TorusMesh.new()
	torus.outer_radius = tire_r
	torus.inner_radius = rim_radius
	tire.mesh = torus
	tire.material_override = black
	tire.rotation.z = PI / 2.0
	tire.scale.y = tire_width / (tire_r - torus.inner_radius)
	pivot.add_child(tire)
	preload("res://scripts/model/bike/parts/tire_tread.gd").add_to(pivot, tire_r, torus.inner_radius, tire_width)
	var authored := rim_scene.instantiate() if rim_scene != null else null
	if authored is Node3D:
		authored.name = "AuthoredRim"
		pivot.add_child(authored)
		return
	if authored != null:
		authored.free()
		push_warning("Rim scene must have a Node3D root")
	for side in [-1, 1]:
		var rim_mesh := TorusMesh.new()
		rim_mesh.inner_radius = rim_radius - 0.06
		rim_mesh.outer_radius = rim_radius + 0.06
		var rim := MeshInstance3D.new()
		rim.mesh = rim_mesh
		rim.material_override = alu
		rim.rotation.z = PI / 2.0
		rim.position.x = side * 0.24
		pivot.add_child(rim)
	for spoke_index in 6:
		var spoke_mesh := BoxMesh.new()
		spoke_mesh.size = Vector3(0.35, rim_radius - 0.25, 0.14)
		var spoke := MeshInstance3D.new()
		spoke.mesh = spoke_mesh
		spoke.material_override = alu
		var angle := TAU * spoke_index / 6.0
		spoke.rotation.x = angle
		spoke.position = Vector3(0.0, cos(angle), sin(angle)) * ((rim_radius + 0.25) * 0.5)
		pivot.add_child(spoke)
	_add_disc(pivot, 0.3, 0.55, alu, dark, 0.0)


# Outer radius of the tyre, scene units. 130/70-17: rim radius 215.9 mm + sidewall 91 mm.
static func tire_outer_radius() -> float:
	return (RIM_DIAMETER_MM * 0.5 + TIRE_WIDTH_MM * TIRE_ASPECT) * MM


# Pitch radius of a sprocket for the chain pitch, scene units.
static func sprocket_radius(teeth: int) -> float:
	return CHAIN_PITCH / (2.0 * sin(PI / teeth))


# Length of the chain loop around two sprockets whose centres are c apart, scene units.
static func loop_length(c: float, r1: float, r2: float) -> float:
	var theta := acos(clampf((r1 - r2) / c, -1.0, 1.0))
	var straight := 2.0 * sqrt(maxf(c * c - (r1 - r2) * (r1 - r2), 0.0))
	return straight + r2 * 2.0 * theta + r1 * (TAU - 2.0 * theta)


# Rear axle z (behind the front sprocket, negative) so the loop equals target length.
# dy: height of the rear axle above the front sprocket.
static func rear_axle_z(dy: float, r1: float, r2: float, target: float) -> float:
	var lo := maxf(absf(dy), absf(r1 - r2)) + 0.0001
	var hi := 40.0
	for i in 60:
		var mid := 0.5 * (lo + hi)
		if loop_length(mid, r1, r2) < target:
			lo = mid
		else:
			hi = mid
	var c := 0.5 * (lo + hi)
	return -sqrt(maxf(c * c - dy * dy, 0.0))


# ground_y: the height the tyre sits on. crank: the front sprocket axis, the gearbox countershaft.
func build(ground_y: float, crank: Vector3, tank_bottom: Vector3 = Vector3.INF, frame_half_width: float = 0.85, has_abs: bool = false, engine_bounds: AABB = AABB(), spec: EngineSpec = null, preset_id: String = "") -> void:
	for c in get_children():
		c.queue_free()
	var steel := _mat(Color(0.45, 0.45, 0.48), 0.4)
	var alu := _mat(Color(0.7, 0.7, 0.72), 0.3)
	var black := _mat(Color(0.14, 0.14, 0.15), 0.8) # tyre: dark grey so it keeps its shape under light
	var dark := _mat(Color(0.15, 0.15, 0.17), 0.6)

	var rear_width := spec.rear_tire_width_mm if spec != null and spec.rear_tire_width_mm > 0.0 else TIRE_WIDTH_MM
	var front_width := spec.front_tire_width_mm if spec != null and spec.front_tire_width_mm > 0.0 else 100.0
	_front_half = front_width * MM * 0.5
	_rear_half = rear_width * MM * 0.5
	var rear_rim := (spec.rear_rim_in if spec != null else 17.0) * 25.4 * 0.5 * MM
	var front_rim := (spec.front_rim_in if spec != null else 17.0) * 25.4 * 0.5 * MM
	var tire_r := rear_rim + rear_width * (spec.rear_tire_aspect if spec != null else TIRE_ASPECT) * MM
	_rear_tire_radius = tire_r
	var wheelbase := spec.wheelbase_mm * MM if spec != null and spec.wheelbase_mm > 0 else WHEELBASE
	_chain_x = maxf(CHAIN_X, rear_width * MM * 0.5 + 0.25)
	var r_front := sprocket_radius(TEETH_FRONT)
	var r_rear := sprocket_radius(TEETH_REAR)
	var axle_y := ground_y + tire_r
	var axle := Vector3(0.0, axle_y, rear_axle_z(axle_y - crank.y, r_front, r_rear, CHAIN_LINKS * CHAIN_PITCH))

	_front_pivot = Node3D.new()
	_front_pivot.name = "FrontSprocketPivot" # named so the built scene can be read as a tree
	_front_pivot.position = Vector3(_chain_x, crank.y, crank.z)
	add_child(_front_pivot)
	_front_pivot.add_child(Sprocket.build(TEETH_FRONT, 0.08, steel))

	rear_axle = axle
	_wheel_pivot = Node3D.new()
	_wheel_pivot.name = "RearWheel"
	_wheel_pivot.position = axle
	add_child(_wheel_pivot)
	_add_tyre(_wheel_pivot, tire_r, rear_width * MM, black, alu, dark, rear_rim, _rim_scene(preset_id, "rear_rim"))

	# front wheel: 80/90-17 tyre (stock front size from owner's manual sources), WHEELBASE ahead of the rear axle,
	# resting on the same ground as the rear
	var front_r := front_rim + front_width * (spec.front_tire_aspect if spec != null else 0.80) * MM
	_front_tire_radius = front_r
	_front_wheel = Node3D.new()
	_front_wheel.name = "FrontWheel"
	_front_wheel.position = Vector3(0.0, ground_y + front_r, axle.z + wheelbase)
	front_axle = _front_wheel.position
	add_child(_front_wheel)
	_add_tyre(_front_wheel, front_r, front_width * MM, black, alu, dark, front_rim, _rim_scene(preset_id, "front_rim"))
	# twin front discs, one either side of the wheel: the standard litre-class layout. The ABS tone ring goes on the
	# outboard disc only, which is what the single front pickup reads.
	BikeBrakes.add_brake_rotor(_front_wheel, -(_front_half + 0.06), FRONT_DISC_RADIUS, steel, dark, has_abs, _rim_scene(preset_id, "front_rotor"))
	BikeBrakes.add_brake_rotor(_front_wheel, _front_half + 0.06, FRONT_DISC_RADIUS, steel, dark, false, null, "Right")
	BikeBrakes.add_brake_rotor(_wheel_pivot, -(_rear_half + 0.06), REAR_DISC_RADIUS, steel, dark, has_abs, _rim_scene(preset_id, "rear_rotor"))
	# the axles: the spindles the wheels turn on. They belong to the fork and the swingarm, not to the wheel, so they are
	# built here and pass through the hub - a wheel with no axle is a wheel hanging in the air.
	var axles := Node3D.new()
	axles.name = "Axles"
	add_child(axles)
	BikeAxles.add_axle(axles, _front_wheel.position, _front_half + FORK_LEG_OFFSET, AXLE_FRONT_RADIUS, steel, dark, 1.0, "Front")
	BikeAxles.add_axle(axles, _wheel_pivot.position, _rear_half + SWINGARM_AXLE_OFFSET, AXLE_REAR_RADIUS, steel, dark, -1.0, "Rear")
	BikeChassis.build_chassis(self, axle, _front_wheel.position, crank, tank_bottom, frame_half_width, steel, dark, engine_bounds)
	BikeCockpit.build_cockpit(self, _head, steel, alu, black) # the yokes, the clip-ons and the levers that work them
	BikeChassis.build_foot_controls(self, crank, frame_half_width, steel, dark)
	BikeBrakes.build_brakes(self, axle, _front_wheel.position, crank, frame_half_width, has_abs, steel, dark)
	var rear := Sprocket.build(TEETH_REAR, 0.08, steel)
	rear.position = Vector3(_chain_x, 0.0, 0.0)
	_wheel_pivot.add_child(rear)

	_rear_radius = r_rear
	_build_chain(Vector2(crank.y, crank.z), Vector2(axle.y, axle.z), r_front, r_rear, steel)


static func _rim_scene(preset_id: String, part: String) -> PackedScene:
	if preset_id.is_empty() or preset_id != preset_id.validate_filename():
		return null
	var path := "res://assets/models/%s/%s.glb" % [preset_id, part]
	return load(path) as PackedScene if ResourceLoader.exists(path, "PackedScene") else null


func add_v3r_bodywork(tank_bottom: Vector3) -> void:
	# Approximate sculpted panels, based on the planned-production bike's asymmetric styling.
	var body := Node3D.new()
	body.name = "V3RBodywork"
	add_child(body)
	var titanium := _mat(Color(0.48, 0.50, 0.52), 0.35)
	var dark := _mat(Color(0.08, 0.09, 0.11), 0.55)
	for side in [-1, 1]:
		var panel := MeshInstance3D.new()
		panel.name = "SidePanel%d" % side
		var shape := BoxMesh.new()
		shape.size = Vector3(0.18, 0.9 if side < 0 else 0.65, 2.2 if side < 0 else 1.6)
		panel.mesh = shape
		panel.material_override = titanium if side < 0 else dark
		panel.position = tank_bottom + Vector3(side * 0.85, -0.65, 0.1 if side < 0 else 0.4)
		panel.rotation.x = -0.2
		body.add_child(panel)


func update(_crank_deg: float, wheel_rpm: float, delta: float, brake: float = 0.0, throttle: float = 0.0, clutch: float = 0.0) -> void:
	if _front_pivot == null:
		return
	if is_instance_valid(_brake_pedal):
		_brake_pedal.rotation.x = clampf(brake, 0.0, 1.0) * 0.25
	# the front brake lever swings in towards the grip, and the clutch lever with it; the throttle tube twists
	# the blades lie along the bars, so a swing about the vertical is what pulls them back towards the grips
	if is_instance_valid(_brake_lever):
		_brake_lever.rotation.y = clampf(brake, 0.0, 1.0) * LEVER_TRAVEL
	if is_instance_valid(_clutch_lever):
		_clutch_lever.rotation.y = -clampf(clutch, 0.0, 1.0) * LEVER_TRAVEL
	if is_instance_valid(_throttle_grip):
		_throttle_grip.rotation.y = -clampf(throttle, 0.0, 1.0) * THROTTLE_TWIST
	if is_instance_valid(_shift_pedal):
		_shift_pedal.rotation.x = move_toward(_shift_pedal.rotation.x, 0.0, SHIFT_PEDAL_RETURN_RATE * maxf(delta, 0.0))
	_wheel_angle = fmod(_wheel_angle + wheel_rpm * 6.0 * delta, 360.0)
	# the chain ties the front sprocket to the wheel, turning FINAL_DRIVE times as fast
	_front_pivot.rotation.x = deg_to_rad(_wheel_angle * FINAL_DRIVE)
	_wheel_pivot.rotation.x = deg_to_rad(_wheel_angle)
	_front_wheel.rotation.x = fmod(_front_wheel.rotation.x + deg_to_rad(wheel_rpm * 6.0 * delta) * _rear_tire_radius / _front_tire_radius, TAU)
	_chain_offset = fmod(_chain_offset + wheel_rpm * TAU / 60.0 * _rear_radius * delta, _path_total)
	_place_links()


func animate_shift(up: bool) -> void:
	if is_instance_valid(_shift_pedal):
		_shift_pedal.rotation.x = -SHIFT_PEDAL_ANGLE if up else SHIFT_PEDAL_ANGLE


func _add_disc(parent: Node3D, radius: float, width: float, mat: Material, marker_mat: Material, x: float) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = width
	mesh.radial_segments = 24
	var disc := MeshInstance3D.new()
	disc.mesh = mesh
	disc.material_override = mat
	disc.position = Vector3(x, 0.0, 0.0)
	disc.rotation.z = PI / 2.0
	parent.add_child(disc)

	var box := BoxMesh.new()
	box.size = Vector3(width * 1.2, radius * 0.25, radius * 0.12)
	var marker := MeshInstance3D.new()
	marker.mesh = box
	marker.material_override = marker_mat
	marker.position = Vector3(x, radius * 0.75, 0.0)
	parent.add_child(marker)


# The chain loop is two tangent lines and two arcs, sampled, then filled with links at pitch spacing.
func _build_chain(a: Vector2, b: Vector2, r1: float, r2: float, mat: Material) -> void:
	var d := b - a
	var c := d.length()
	var ang := d.angle()
	var theta := acos(clampf((r1 - r2) / c, -1.0, 1.0))
	var n_up := ang + theta
	var n_down := ang - theta

	var pts := PackedVector2Array()
	_line(pts, a + Vector2.from_angle(n_up) * r1, b + Vector2.from_angle(n_up) * r2)
	_arc(pts, b, r2, n_up, n_down)
	_line(pts, b + Vector2.from_angle(n_down) * r2, a + Vector2.from_angle(n_down) * r1)
	_arc(pts, a, r1, n_down, n_up - TAU)

	_path = pts
	_path_cum = PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		_path_cum.append(_path_cum[i - 1] + pts[i].distance_to(pts[i - 1]))
	_path_total = _path_cum[_path_cum.size() - 1]

	# side plates: two per link, one each side of the rollers
	var plate := BoxMesh.new()
	plate.size = Vector3(PLATE_THICKNESS, PLATE_HEIGHT, CHAIN_PITCH)
	_links = _multimesh(plate, 2 * CHAIN_LINKS)
	_add_multimesh(_links, mat)
	# rollers: one at each joint, axis along X
	var roller := CylinderMesh.new()
	roller.top_radius = ROLLER_RADIUS
	roller.bottom_radius = ROLLER_RADIUS
	roller.height = ROLLER_LENGTH
	roller.radial_segments = 12
	_rollers = _multimesh(roller, CHAIN_LINKS)
	_add_multimesh(_rollers, _mat(Color(0.7, 0.7, 0.72), 0.3))
	# master link clip: a small pin clip on the outside of link 0, where the chain joins
	var clip := BoxMesh.new()
	clip.size = Vector3(0.02, 0.02, 0.03)
	_clip = _multimesh(clip, 1)
	_add_multimesh(_clip, _mat(Color(0.8, 0.8, 0.2), 0.4))
	_place_links()


func _multimesh(mesh: Mesh, count: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	return mm


func _add_multimesh(mm: MultiMesh, mat: Material) -> void:
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)


# Puts every link on the loop, shifted by the chain's travel so far. Links are spaced
# evenly, so the loop stays closed even as it moves.
func _place_links() -> void:
	var count := CHAIN_LINKS
	var spacing := _path_total / count
	var idx := 0
	for k in count:
		var s := fmod((k + 0.5) * spacing + _chain_offset, _path_total)
		idx = 0
		while idx < _path_cum.size() - 2 and _path_cum[idx + 1] < s:
			idx += 1
		var seg := _path[idx + 1] - _path[idx]
		var t := seg.normalized() if seg.length() > 0.0 else Vector2.RIGHT
		var span := _path_cum[idx + 1] - _path_cum[idx]
		var p := _path[idx].lerp(_path[idx + 1], (s - _path_cum[idx]) / span if span > 0.0 else 0.0)
		var link_basis := Basis(Vector3.RIGHT, atan2(-t.x, t.y)) # plates' long axis (Z) follows the chain
		var joint := Vector3(_chain_x, p.x, p.y)
		_links.set_instance_transform(2 * k, Transform3D(link_basis, joint + Vector3(-PLATE_OFFSET, 0.0, 0.0)))
		_links.set_instance_transform(2 * k + 1, Transform3D(link_basis, joint + Vector3(PLATE_OFFSET, 0.0, 0.0)))
		_rollers.set_instance_transform(k, Transform3D(link_basis * ROLLER_TURN, joint))
		if k == 0:
			_clip.set_instance_transform(0, Transform3D(link_basis, joint + Vector3(PLATE_OFFSET + 0.012, 0.0, 0.0)))


func _line(pts: PackedVector2Array, from: Vector2, to: Vector2) -> void:
	var steps := 32
	for i in range(0, steps + 1):
		pts.append(from.lerp(to, float(i) / steps))


func _arc(pts: PackedVector2Array, centre: Vector2, r: float, from_angle: float, to_angle: float) -> void:
	var steps := 64
	for i in range(0, steps + 1):
		var ang := lerpf(from_angle, to_angle, float(i) / steps)
		pts.append(centre + Vector2.from_angle(ang) * r)


static func _mat(c: Color, rough: float) -> StandardMaterial3D:
	return BikeMaterials.make(c, rough)
