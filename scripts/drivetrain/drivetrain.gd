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
var rear_axle := Vector3.ZERO # rear axle centre, set by build


# Outer radius of the 100/80-17 front tyre, scene units: rim radius plus an 80 mm sidewall (80% of 100 mm).
static func front_tire_outer_radius() -> float:
	return (RIM_DIAMETER_MM * 0.5 + 100.0 * 0.80) * MM


# One wheel: tyre torus and rim disc with a spoke marker, centred on the pivot.
func _add_tyre(pivot: Node3D, tire_r: float, black: Material, alu: Material, dark: Material) -> void:
	var tire := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.outer_radius = tire_r
	torus.inner_radius = tire_r - 1.0 # 0.5 unit tyre cross-section
	tire.mesh = torus
	tire.material_override = black
	tire.rotation.z = PI / 2.0
	pivot.add_child(tire)
	_add_disc(pivot, tire_r - 1.0, 0.2, alu, dark, 0.0)


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
func build(ground_y: float, crank: Vector3) -> void:
	for c in get_children():
		c.queue_free()
	var steel := _mat(Color(0.45, 0.45, 0.48), 0.4)
	var alu := _mat(Color(0.7, 0.7, 0.72), 0.3)
	var black := _mat(Color(0.14, 0.14, 0.15), 0.8) # tyre: dark grey so it keeps its shape under light
	var dark := _mat(Color(0.15, 0.15, 0.17), 0.6)

	var tire_r := tire_outer_radius()
	var r_front := sprocket_radius(TEETH_FRONT)
	var r_rear := sprocket_radius(TEETH_REAR)
	var axle_y := ground_y + tire_r
	var axle := Vector3(0.0, axle_y, rear_axle_z(axle_y - crank.y, r_front, r_rear, CHAIN_LINKS * CHAIN_PITCH))

	_front_pivot = Node3D.new()
	_front_pivot.position = Vector3(CHAIN_X, crank.y, crank.z)
	add_child(_front_pivot)
	_front_pivot.add_child(Sprocket.build(TEETH_FRONT, 0.08, steel))

	rear_axle = axle
	_wheel_pivot = Node3D.new()
	_wheel_pivot.position = axle
	add_child(_wheel_pivot)
	_add_tyre(_wheel_pivot, tire_r, black, alu, dark)

	# front wheel: 80/90-17 tyre (stock front size from owner's manual sources), WHEELBASE ahead of the rear axle,
	# resting on the same ground as the rear
	var front_r := front_tire_outer_radius()
	_front_wheel = Node3D.new()
	_front_wheel.position = Vector3(0.0, ground_y + front_r, axle.z + WHEELBASE)
	add_child(_front_wheel)
	_add_tyre(_front_wheel, front_r, black, alu, dark)
	var rear := Sprocket.build(TEETH_REAR, 0.08, steel)
	rear.position = Vector3(CHAIN_X, 0.0, 0.0)
	_wheel_pivot.add_child(rear)

	_rear_radius = r_rear
	_build_chain(Vector2(crank.y, crank.z), Vector2(axle.y, axle.z), r_front, r_rear, steel)


# crank_deg: 0..720 crank angle. wheel_rpm: from the vehicle speed, so the wheel matches the road.
# The chain moves at the rear sprocket's pitch speed, so its links travel with the wheel.
func update(_crank_deg: float, wheel_rpm: float, delta: float) -> void:
	if _front_pivot == null:
		return
	_wheel_angle = fmod(_wheel_angle + wheel_rpm * 6.0 * delta, 360.0)
	# the chain ties the front sprocket to the wheel, turning FINAL_DRIVE times as fast
	_front_pivot.rotation.x = deg_to_rad(_wheel_angle * FINAL_DRIVE)
	_wheel_pivot.rotation.x = deg_to_rad(_wheel_angle)
	_front_wheel.rotation.x = deg_to_rad(_wheel_angle)
	_chain_offset = fmod(_chain_offset + wheel_rpm * TAU / 60.0 * _rear_radius * delta, _path_total)
	_place_links()


# A disc with its axis along X at x_offset, plus a marker on its face so spin is visible.
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
		var joint := Vector3(CHAIN_X, p.x, p.y)
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
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m
