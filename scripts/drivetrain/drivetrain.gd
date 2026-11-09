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
var _rear_tire_radius := 0.0
var _front_tire_radius := 0.0
var _chain_x := CHAIN_X
var front_axle := Vector3.ZERO
var _front_half := 0.5
var _rear_half := 0.65
var rear_axle := Vector3.ZERO # rear axle centre, set by build
var _brake_pedal: Node3D
var _shift_pedal: Node3D
const SHIFT_PEDAL_ANGLE := 0.26
const SHIFT_PEDAL_RETURN_RATE := 2.0


# Outer radius of the 100/80-17 front tyre, scene units: rim radius plus an 80 mm sidewall (80% of 100 mm).
static func front_tire_outer_radius() -> float:
	return (RIM_DIAMETER_MM * 0.5 + 100.0 * 0.80) * MM


# One wheel: tyre, rim, spokes and hub, centred on the pivot.
func _add_tyre(pivot: Node3D, tire_r: float, tire_width: float, black: Material, alu: Material, dark: Material, rim_radius: float = RIM_DIAMETER_MM * 0.5 * MM) -> void:
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
	preload("res://scripts/drivetrain/tire_tread.gd").add_to(pivot, tire_r, torus.inner_radius, tire_width)
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
func build(ground_y: float, crank: Vector3, tank_bottom: Vector3 = Vector3.INF, frame_half_width: float = 0.85, has_abs: bool = false, engine_bounds: AABB = AABB(), spec: EngineSpec = null) -> void:
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
	_front_pivot.position = Vector3(_chain_x, crank.y, crank.z)
	add_child(_front_pivot)
	_front_pivot.add_child(Sprocket.build(TEETH_FRONT, 0.08, steel))

	rear_axle = axle
	_wheel_pivot = Node3D.new()
	_wheel_pivot.position = axle
	add_child(_wheel_pivot)
	_add_tyre(_wheel_pivot, tire_r, rear_width * MM, black, alu, dark, rear_rim)

	# front wheel: 80/90-17 tyre (stock front size from owner's manual sources), WHEELBASE ahead of the rear axle,
	# resting on the same ground as the rear
	var front_r := front_rim + front_width * (spec.front_tire_aspect if spec != null else 0.80) * MM
	_front_tire_radius = front_r
	_front_wheel = Node3D.new()
	_front_wheel.position = Vector3(0.0, ground_y + front_r, axle.z + wheelbase)
	front_axle = _front_wheel.position
	add_child(_front_wheel)
	_add_tyre(_front_wheel, front_r, front_width * MM, black, alu, dark, front_rim)
	_add_brake_rotor(_front_wheel, -(_front_half + 0.06), 1.1, steel, dark, has_abs)
	_add_brake_rotor(_wheel_pivot, -(_rear_half + 0.06), 1.0, steel, dark, has_abs)
	_build_chassis(axle, _front_wheel.position, crank, tank_bottom, frame_half_width, steel, dark, engine_bounds)
	_build_foot_controls(crank, frame_half_width, steel, dark)
	_build_brakes(axle, _front_wheel.position, crank, frame_half_width, has_abs, steel, dark)
	var rear := Sprocket.build(TEETH_REAR, 0.08, steel)
	rear.position = Vector3(_chain_x, 0.0, 0.0)
	_wheel_pivot.add_child(rear)

	_rear_radius = r_rear
	_build_chain(Vector2(crank.y, crank.z), Vector2(axle.y, axle.z), r_front, r_rear, steel)


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


func _add_brake_rotor(wheel: Node3D, x: float, radius: float, material: Material, dark: Material, has_abs: bool) -> void:
	var rotor := MeshInstance3D.new()
	rotor.name = "BrakeRotor"
	rotor.mesh = _rotor_mesh(radius)
	var rotor_material := material.duplicate() as StandardMaterial3D
	rotor_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	rotor_material.metallic = 0.6
	rotor.material_override = rotor_material
	rotor.position.x = x
	wheel.add_child(rotor)
	var carrier := MeshInstance3D.new()
	carrier.name = "RotorCarrier"
	carrier.mesh = _ring_mesh(radius * 0.28, radius * 0.70, 0.055, false)
	var carrier_material := dark.duplicate() as StandardMaterial3D
	carrier_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	carrier.material_override = carrier_material
	carrier.position.x = x + 0.025
	wheel.add_child(carrier)
	for i in 6:
		var angle := TAU * i / 6.0
		_add_member(wheel, "RotorBolt%d" % i, Vector3(x - 0.035, radius * 0.58 * cos(angle), radius * 0.58 * sin(angle)), Vector3(x + 0.055, radius * 0.58 * cos(angle), radius * 0.58 * sin(angle)), 0.045, material)
	if has_abs:
		var tone := MeshInstance3D.new()
		tone.name = "ABSToneRing"
		tone.mesh = _ring_mesh(radius * 0.38, radius * 0.53, 0.025, true)
		tone.material_override = rotor_material
		tone.position.x = x - 0.09
		wheel.add_child(tone)


# Generic hydraulic layout: the calipers and hoses are fixed to the chassis, not the wheels.
func _build_brakes(rear: Vector3, front: Vector3, countershaft: Vector3, half_width: float, has_abs: bool, steel: Material, dark: Material) -> void:
	var brakes := Node3D.new()
	brakes.name = "BrakeHardware"
	add_child(brakes)
	var front_caliper := front + Vector3(-(_front_half + 0.06), 0.35, -0.99)
	var rear_caliper := rear + Vector3(-(_rear_half + 0.06), 0.82, 0.45)
	for item in [["FrontCaliper", front_caliper], ["RearCaliper", rear_caliper]]:
		var caliper := MeshInstance3D.new()
		caliper.name = item[0]
		var shape := BoxMesh.new()
		shape.size = Vector3(0.28, 0.46, 0.38)
		caliper.mesh = shape
		caliper.material_override = steel
		caliper.position = item[1]
		brakes.add_child(caliper)
	var head := front + Vector3(0.0, 4.0, -1.1)
	var front_master := head + Vector3(-1.15, 0.66, -0.16)
	var rear_master := countershaft + Vector3(-half_width - 0.18, 0.05, -1.15)
	var reservoir_mat := _mat(Color(0.72, 0.69, 0.55), 0.55)
	for item in [["FrontReservoir", front_master], ["RearReservoir", rear_master + Vector3(0, 0.45, 0)]]:
		var reservoir := MeshInstance3D.new()
		reservoir.name = item[0]
		var shape := CylinderMesh.new()
		shape.top_radius = 0.13
		shape.bottom_radius = 0.11
		shape.height = 0.25
		reservoir.mesh = shape
		reservoir.material_override = reservoir_mat
		reservoir.position = item[1]
		brakes.add_child(reservoir)
		_add_member(brakes, "%sCap" % item[0], item[1] + Vector3(0, 0.12, 0), item[1] + Vector3(0, 0.16, 0), 0.14, dark)
	_add_member(brakes, "RearMasterCylinder", rear_master, rear_master + Vector3(0, -0.3, 0), 0.09, steel)
	_add_member(brakes, "RearReservoirHose", rear_master, rear_master + Vector3(0, 0.34, 0), 0.025, dark)
	var front_route := head + Vector3(-(_front_half + 0.06), 0.0, 0.0)
	if has_abs:
		for item in [["FrontABSSensor", front, _front_half, 1.1], ["RearABSSensor", rear, _rear_half, 1.0]]:
			var sensor_pos: Vector3 = item[1] + Vector3(-(float(item[2]) + 0.15), float(item[3]) * 0.54, 0.0)
			_add_member(brakes, item[0], sensor_pos + Vector3(-0.22, 0.08, 0), sensor_pos, 0.055, dark)
		var module_pos := countershaft + Vector3(-half_width - 0.10, 0.65, -0.65)
		var module := MeshInstance3D.new()
		module.name = "ABSModule"
		var block := BoxMesh.new()
		block.size = Vector3(0.32, 0.36, 0.45)
		module.mesh = block
		module.material_override = steel
		module.position = module_pos
		brakes.add_child(module)
		_hose(brakes, "FrontFeed", [front_master, front_route, module_pos], dark)
		_hose(brakes, "FrontBrakeHose", [module_pos, front_route, front_caliper], dark)
		_hose(brakes, "RearFeed", [rear_master, module_pos], dark)
		_hose(brakes, "RearBrakeHose", [module_pos, rear_caliper], dark)
	else:
		_hose(brakes, "FrontBrakeHose", [front_master, front_route, front_caliper], dark)
		_hose(brakes, "RearBrakeHose", [rear_master, rear_caliper], dark)


func _hose(parent: Node3D, hose_name: String, points: Array, material: Material) -> void:
	for i in points.size() - 1:
		_add_member(parent, "%s%d" % [hose_name, i], points[i], points[i + 1], 0.025, material)


func _rotor_mesh(radius: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Each sector is a curved quadrilateral with an eight-sided through-hole.
	for segment in 32:
		var mid := TAU * (segment + 0.5) / 32.0
		var half := TAU / 64.0
		var perimeter := [Vector2(0.70, -1), Vector2(0.70, 0), Vector2(0.70, 1), Vector2(0.85, 1), Vector2(1.0, 1), Vector2(1.0, 0), Vector2(1.0, -1), Vector2(0.85, -1)]
		var holes := []
		var edges := []
		for i in 8:
			var a := mid + float(perimeter[i].y) * half
			var r := radius * float(perimeter[i].x)
			edges.append(Vector3(0, r * cos(a), r * sin(a)))
			var h := PI * 1.25 - TAU * i / 8.0
			var hole_r := radius * (0.85 + 0.045 * cos(h))
			var hole_a := mid + half * 0.46 * sin(h)
			holes.append(Vector3(0, hole_r * cos(hole_a), hole_r * sin(hole_a)))
		for i in 8:
			var j := (i + 1) % 8
			for side in [-1.0, 1.0]:
				var offset := Vector3(side * 0.025, 0, 0)
				for point in [edges[i], edges[j], holes[i], holes[i], edges[j], holes[j]]:
					surface.add_vertex(point + offset)
			for point in [holes[i] + Vector3(-0.025, 0, 0), holes[j] + Vector3(-0.025, 0, 0), holes[i] + Vector3(0.025, 0, 0), holes[i] + Vector3(0.025, 0, 0), holes[j] + Vector3(-0.025, 0, 0), holes[j] + Vector3(0.025, 0, 0)]:
				surface.add_vertex(point)
	surface.generate_normals()
	return surface.commit()


func _ring_mesh(inner: float, outer: float, thickness: float, slotted: bool) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment in 96:
		var a := TAU * segment / 96.0
		var b := TAU * (segment + 1) / 96.0
		# Alternate short outer teeth with the continuous inner band for the sensor ring.
		var r := inner + (outer - inner) * 0.45 if slotted and segment % 2 == 0 else outer
		for side in [-1.0, 1.0]:
			var x: float = side * thickness * 0.5
			var p := Vector3(x, inner * cos(a), inner * sin(a))
			var q := Vector3(x, r * cos(a), r * sin(a))
			var s := Vector3(x, inner * cos(b), inner * sin(b))
			var t := Vector3(x, r * cos(b), r * sin(b))
			for point in [p, q, s, s, q, t]:
				surface.add_vertex(point)
	surface.generate_normals()
	return surface.commit()


func _build_chassis(rear: Vector3, front: Vector3, crank: Vector3, tank_bottom: Vector3, frame_half_width: float, steel: Material, dark: Material, engine_bounds: AABB) -> void:
	var chassis := Node3D.new()
	chassis.name = "Chassis"
	add_child(chassis)
	var head := front + Vector3(0.0, 4.0, -1.1)
	var upper := crank + Vector3(0.0, 2.8, -0.55)
	var pivot := crank + Vector3(0.0, 0.15, -0.45)
	if engine_bounds.has_volume():
		# Keep the side rails outside the engine and route the rear upright behind it.
		frame_half_width = maxf(frame_half_width, maxf(absf(engine_bounds.position.x), absf(engine_bounds.end.x)) + 0.25)
		upper.y = maxf(upper.y, engine_bounds.end.y + 0.25)
		upper.z = minf(upper.z, engine_bounds.position.z - 0.25)
		pivot.z = upper.z
	for side in [-1, 1]:
		var fork_bottom := front + Vector3(side * (_front_half + 0.16), 0.0, 0.0)
		var fork_top := head + Vector3(side * (_front_half + 0.16), 0.5, -0.14)
		var fork_mid := fork_bottom.lerp(fork_top, 0.55)
		_add_member(chassis, "ForkLower%d" % side, fork_bottom, fork_mid, 0.14, dark)
		_add_member(chassis, "ForkUpper%d" % side, fork_mid, fork_top, 0.09, steel)
		var frame_head := head + Vector3(side * 0.65, 0.0, 0.0)
		var frame_upper := upper + Vector3(side * frame_half_width, 0.0, 0.0)
		var frame_pivot := pivot + Vector3(side * frame_half_width, 0.0, 0.0)
		_add_member(chassis, "FrameTop%d" % side, frame_head, frame_upper, 0.11, dark)
		_add_member(chassis, "FrameDown%d" % side, frame_upper, frame_pivot, 0.12, dark)
		var axle_end := rear + Vector3(side * (_rear_half + 0.18), 0.0, 0.0)
		_add_swingarm_beam(chassis, "Swingarm%d" % side, frame_pivot, axle_end, dark)
		# Axle plate and adjuster make the end of each arm visibly connect to the wheel.
		_add_member(chassis, "AxlePlate%d" % side, axle_end + Vector3(0, -0.16, -0.16), axle_end + Vector3(0, 0.16, 0.16), 0.16, steel)
		_add_member(chassis, "AxleAdjuster%d" % side, axle_end + Vector3(0, 0, -0.36), axle_end + Vector3(0, 0, -0.06), 0.045, steel)
		if tank_bottom.is_finite():
			var tank_rear := tank_bottom + Vector3(side * 0.6, -0.08, -0.8)
			var tank_front := tank_bottom + Vector3(side * 0.6, -0.08, 0.8)
			var seat_rear := tank_bottom + Vector3(side * 0.6, -0.22, -4.0)
			_add_member(chassis, "TankRail%d" % side, tank_rear, tank_front, 0.09, dark)
			_add_member(chassis, "TankMount%d" % side, frame_upper, tank_rear, 0.09, dark)
			_add_member(chassis, "TankFront%d" % side, tank_front, frame_head, 0.09, dark)
			_add_member(chassis, "SeatRail%d" % side, tank_rear, seat_rear, 0.08, dark)
			_add_member(chassis, "Subframe%d" % side, frame_pivot, seat_rear, 0.08, dark)
	_add_member(chassis, "SwingarmPivot", pivot + Vector3(-frame_half_width - 0.08, 0, 0), pivot + Vector3(frame_half_width + 0.08, 0, 0), 0.16, steel)
	_add_member(chassis, "SwingarmBrace", pivot.lerp(rear, 0.42) + Vector3(-_rear_half - 0.18, 0, 0), pivot.lerp(rear, 0.42) + Vector3(_rear_half + 0.18, 0, 0), 0.11, dark)
	# Stationary rear axle spans both swingarm ends; the wheel rotates around it.
	_add_member(chassis, "AxleRear", rear + Vector3(-_rear_half - 0.3, 0, 0), rear + Vector3(_rear_half + 0.3, 0, 0), 0.09, steel)
	for side in [-1.0, 1.0]:
		_add_member(chassis, "AxleNut%s" % str(int(side)), rear + Vector3(side * (_rear_half + 0.24), 0, 0), rear + Vector3(side * (_rear_half + 0.34), 0, 0), 0.14, steel)
	_add_member(chassis, "SteeringStem", head + Vector3(0.0, -0.45, 0.12), head + Vector3(0.0, 0.5, -0.14), 0.18, dark)
	_add_member(chassis, "Handlebar", head + Vector3(-1.3, 0.62, -0.16), head + Vector3(1.3, 0.62, -0.16), 0.055, steel)
	if tank_bottom.is_finite():
		var seat := MeshInstance3D.new()
		seat.name = "Seat"
		var seat_mesh := CapsuleMesh.new()
		seat_mesh.radius = 0.7
		seat_mesh.height = 3.0
		seat.mesh = seat_mesh
		seat.material_override = dark
		seat.position = tank_bottom + Vector3(0.0, 0.05, -2.55)
		seat.rotation.x = PI / 2.0
		seat.scale.z = 0.25
		chassis.add_child(seat)
		var shock_top := tank_bottom + Vector3(0.0, -0.3, -3.1)
		var shock_bottom := pivot.lerp(rear, 0.42)
		var shock_mid := shock_bottom.lerp(shock_top, 0.48)
		_add_member(chassis, "ShockBody", shock_bottom, shock_mid, 0.13, dark)
		_add_member(chassis, "ShockRod", shock_mid, shock_top, 0.07, steel)


func _add_swingarm_beam(parent: Node3D, member_name: String, start: Vector3, end: Vector3, material: Material) -> void:
	var beam := MeshInstance3D.new()
	beam.name = member_name
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.25, start.distance_to(end), 0.34)
	beam.mesh = mesh
	beam.material_override = material
	beam.position = (start + end) * 0.5
	beam.quaternion = Quaternion(Vector3.UP, (end - start).normalized())
	parent.add_child(beam)


func _add_member(parent: Node3D, member_name: String, start: Vector3, end: Vector3, radius: float, material: Material) -> void:
	var member := MeshInstance3D.new()
	member.name = member_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = start.distance_to(end)
	mesh.radial_segments = 16
	member.mesh = mesh
	member.material_override = material
	member.position = (start + end) * 0.5
	member.quaternion = Quaternion(Vector3.UP, (end - start).normalized())
	parent.add_child(member)


# crank_deg: 0..720 crank angle. wheel_rpm: from the vehicle speed, so the wheel matches the road.
# The chain moves at the rear sprocket's pitch speed, so its links travel with the wheel.
func update(_crank_deg: float, wheel_rpm: float, delta: float, brake: float = 0.0) -> void:
	if _front_pivot == null:
		return
	if is_instance_valid(_brake_pedal):
		_brake_pedal.rotation.x = clampf(brake, 0.0, 1.0) * 0.25
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


# Generic rearsets, arranged around the frame pivot. +X is the chain/shift side.
func _build_foot_controls(countershaft: Vector3, half_width: float, steel: Material, rubber: Material) -> void:
	var controls := Node3D.new()
	controls.name = "FootControls"
	add_child(controls)
	for side in [-1, 1]:
		var mount := countershaft + Vector3(side * (half_width + 0.06), 0.0, -0.75)
		var peg_base := mount + Vector3(side * 0.14, -0.38, -0.25)
		var peg_end := peg_base + Vector3(side * 0.85, 0.0, 0.0)
		_add_member(controls, "RearsetUpper%d" % side, mount, peg_base, 0.07, steel)
		_add_member(controls, "RearsetBrace%d" % side, mount + Vector3(0, 0.35, -0.6), peg_base, 0.06, steel)
		_add_member(controls, "Footpeg%d" % side, peg_base, peg_end, 0.11, rubber)
		_add_member(controls, "PegEnd%d" % side, peg_end, peg_end + Vector3(side * 0.06, 0, 0), 0.12, steel)
		var pedal := Node3D.new()
		pedal.name = "ShiftPedal" if side == 1 else "RearBrakePedal"
		pedal.position = peg_base + Vector3(side * 0.2, -0.08, 0.0)
		controls.add_child(pedal)
		_add_member(pedal, "Lever", Vector3.ZERO, Vector3(0, -0.04, 0.92), 0.055, steel)
		_add_member(pedal, "ToePad", Vector3(0, -0.04, 0.92), Vector3(side * 0.3, -0.04, 0.92), 0.09, rubber)
		_add_member(pedal, "Pivot", Vector3(-0.08, 0, 0), Vector3(0.08, 0, 0), 0.10, steel)
		if side == -1:
			_brake_pedal = pedal
		else:
			_shift_pedal = pedal


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
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m
