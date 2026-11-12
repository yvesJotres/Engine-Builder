class_name BikeChassis
extends RefCounted

# The frame: fork legs, rails, swingarm, shock and the foot controls.
# Every builder that adds nodes takes the node it draws into as `host`.

const FORK_LEG_OFFSET := 0.30 # fork legs this far out from the tyre's half width, so a caliper fits between disc and leg
const SWINGARM_AXLE_OFFSET := 0.18 # where the swingarm arms clamp the rear axle


static func build_chassis(host: Node3D, rear: Vector3, front: Vector3, crank: Vector3, tank_bottom: Vector3, frame_half_width: float, steel: Material, dark: Material, engine_bounds: AABB) -> void:
	var chassis := Node3D.new()
	chassis.name = "Chassis"
	host.add_child(chassis)
	host._head = front + Vector3(0.0, 4.0, -1.1)
	var head: Vector3 = host._head
	var upper := crank + Vector3(0.0, 2.8, -0.55)
	var pivot := crank + Vector3(0.0, 0.15, -0.45)
	if engine_bounds.has_volume():
		# Keep the side rails outside the engine and route the rear upright behind it.
		frame_half_width = maxf(frame_half_width, maxf(absf(engine_bounds.position.x), absf(engine_bounds.end.x)) + 0.25)
		upper.y = maxf(upper.y, engine_bounds.end.y + 0.25)
		upper.z = minf(upper.z, engine_bounds.position.z - 0.25)
		pivot.z = upper.z
	for side in [-1, 1]:
		# the legs sit clear of the discs: a radial caliper has to fit between the disc face and the leg
		var fork_bottom: Vector3 = front + Vector3(side * (host._front_half + FORK_LEG_OFFSET), 0.0, 0.0)
		var fork_top: Vector3 = head + Vector3(side * (host._front_half + FORK_LEG_OFFSET), 0.5, -0.14)
		var fork_mid := fork_bottom.lerp(fork_top, 0.55)
		BikeChassis.add_member(chassis, "ForkLower%d" % side, fork_bottom, fork_mid, 0.14, dark)
		BikeChassis.add_member(chassis, "ForkUpper%d" % side, fork_mid, fork_top, 0.09, steel)
		var frame_head := head + Vector3(side * 0.65, 0.0, 0.0)
		var frame_upper := upper + Vector3(side * frame_half_width, 0.0, 0.0)
		var frame_pivot := pivot + Vector3(side * frame_half_width, 0.0, 0.0)
		BikeChassis.add_member(chassis, "FrameTop%d" % side, frame_head, frame_upper, 0.11, dark)
		BikeChassis.add_member(chassis, "FrameDown%d" % side, frame_upper, frame_pivot, 0.12, dark)
		var axle_end: Vector3 = rear + Vector3(side * (host._rear_half + 0.18), 0.0, 0.0)
		# the swingarm itself is built after the loop, in one piece: see BikeSwingarm.build
		if tank_bottom.is_finite():
			var tank_rear := tank_bottom + Vector3(side * 0.6, -0.08, -0.8)
			var tank_front := tank_bottom + Vector3(side * 0.6, -0.08, 0.8)
			var seat_rear := tank_bottom + Vector3(side * 0.6, -0.22, -4.0)
			BikeChassis.add_member(chassis, "TankRail%d" % side, tank_rear, tank_front, 0.09, dark)
			BikeChassis.add_member(chassis, "TankMount%d" % side, frame_upper, tank_rear, 0.09, dark)
			BikeChassis.add_member(chassis, "TankFront%d" % side, tank_front, frame_head, 0.09, dark)
			BikeChassis.add_member(chassis, "SeatRail%d" % side, tank_rear, seat_rear, 0.08, dark)
			BikeChassis.add_member(chassis, "Subframe%d" % side, frame_pivot, seat_rear, 0.08, dark)
	# one casting: tapered arms, top ribs, pivot tube, cross-brace, axle blocks, chain slider
	BikeSwingarm.build(chassis, pivot, rear, host._rear_half, frame_half_width, steel, dark)
	# Stationary rear axle spans both swingarm ends; the wheel rotates around it.
	BikeChassis.add_member(chassis, "AxleRear", rear + Vector3(-host._rear_half - 0.3, 0, 0), rear + Vector3(host._rear_half + 0.3, 0, 0), 0.09, steel)
	for side in [-1.0, 1.0]:
		BikeChassis.add_member(chassis, "AxleNut%s" % str(int(side)), rear + Vector3(side * (host._rear_half + 0.24), 0, 0), rear + Vector3(side * (host._rear_half + 0.34), 0, 0), 0.14, steel)
	BikeChassis.add_member(chassis, "SteeringStem", head + Vector3(0.0, -0.45, 0.12), head + Vector3(0.0, 0.5, -0.14), 0.18, dark)
	BikeChassis.add_member(chassis, "Handlebar", head + Vector3(-1.3, 0.62, -0.16), head + Vector3(1.3, 0.62, -0.16), 0.055, steel)
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
		BikeChassis.add_member(chassis, "ShockBody", shock_bottom, shock_mid, 0.13, dark)
		BikeChassis.add_member(chassis, "ShockRod", shock_mid, shock_top, 0.07, steel)


static func add_member(parent: Node3D, member_name: String, start: Vector3, end: Vector3, radius: float, material: Material) -> void:
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
# brake, throttle and clutch are the rider's inputs, 0..1: they move the pedal, the levers and the twist grip.


static func build_foot_controls(host: Node3D, countershaft: Vector3, half_width: float, steel: Material, rubber: Material) -> void:
	var controls := Node3D.new()
	controls.name = "FootControls"
	host.add_child(controls)
	for side in [-1, 1]:
		var mount := countershaft + Vector3(side * (half_width + 0.06), 0.0, -0.75)
		var peg_base := mount + Vector3(side * 0.14, -0.38, -0.25)
		var peg_end := peg_base + Vector3(side * 0.85, 0.0, 0.0)
		BikeChassis.add_member(controls, "RearsetUpper%d" % side, mount, peg_base, 0.07, steel)
		BikeChassis.add_member(controls, "RearsetBrace%d" % side, mount + Vector3(0, 0.35, -0.6), peg_base, 0.06, steel)
		BikeChassis.add_member(controls, "Footpeg%d" % side, peg_base, peg_end, 0.11, rubber)
		BikeChassis.add_member(controls, "PegEnd%d" % side, peg_end, peg_end + Vector3(side * 0.06, 0, 0), 0.12, steel)
		var pedal := Node3D.new()
		pedal.name = "ShiftPedal" if side == 1 else "RearBrakePedal"
		pedal.position = peg_base + Vector3(side * 0.2, -0.08, 0.0)
		controls.add_child(pedal)
		BikeChassis.add_member(pedal, "Lever", Vector3.ZERO, Vector3(0, -0.04, 0.92), 0.055, steel)
		BikeChassis.add_member(pedal, "ToePad", Vector3(0, -0.04, 0.92), Vector3(side * 0.3, -0.04, 0.92), 0.09, rubber)
		BikeChassis.add_member(pedal, "Pivot", Vector3(-0.08, 0, 0), Vector3(0.08, 0, 0), 0.10, steel)
		if side == -1:
			host._brake_pedal = pedal
		else:
			host._shift_pedal = pedal


# A disc with its axis along X at x_offset, plus a marker on its face so spin is visible.
