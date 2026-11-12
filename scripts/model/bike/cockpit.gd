class_name BikeCockpit
extends RefCounted

# The steering head and the rider's controls: yokes, stem nut, clip-ons, grips, levers and the lever perch.
# Every builder that adds nodes takes the node it draws into as `host`.

const FORK_LEG_OFFSET := BikeChassis.FORK_LEG_OFFSET # the bar clamps to the fork tube
const BAR_END_X := 4.05 # where the bar ends, out from the centre line: 700 mm across between the grips
const BAR_END_Z := -1.90 # and this far behind the steering head, swept back over the tank as clip-ons are
const BAR_RADIUS := 0.10 # 20 mm tube
const GRIP_LENGTH := 1.20 # 120 mm of grip
const GRIP_RADIUS := 0.15 # 30 mm across, the usual grip size
const LEVER_LENGTH := 1.70 # 170 mm lever
const LEVER_PIVOT_OFFSET := Vector3(0.0, 0.0, 0.20) # the pivot sits 20 mm forward of the bar, as a radial master's does


static func clip_on(host: Node3D, head: Vector3, side: float) -> Array:
	var leg_x: float = host._front_half + FORK_LEG_OFFSET
	var start := head + Vector3(side * leg_x, 0.26, -0.16) # on the fork tube, where the clamp is
	var finish := head + Vector3(side * BAR_END_X, 0.14, BAR_END_Z)
	var dir := (finish - start).normalized()
	return [start, finish, dir, finish - dir * GRIP_LENGTH] # start, end, direction, where the grip begins


# The steering head: top and bottom yokes clamping the fork tubes, the stem nut between them, and the clip-ons those
# yokes carry. Levers and a twisting throttle live here too, because that is where the rider's hands are.
#   head  the steering head the chassis was built around


static func build_cockpit(host: Node3D, head: Vector3, steel: Material, alu: Material, rubber: Material) -> void:
	var cockpit := Node3D.new()
	cockpit.name = "Cockpit"
	host.add_child(cockpit)
	var leg_x: float = host._front_half + FORK_LEG_OFFSET
	# the two yokes: castings that pinch both fork tubes and carry the steering stem between them
	for item in [["TopYoke", Vector3(2.0 * leg_x + 0.34, 0.16, 0.46), Vector3(0.0, 0.44, -0.16), alu],
			["BottomYoke", Vector3(2.0 * leg_x + 0.22, 0.14, 0.40), Vector3(0.0, 0.10, -0.20), alu]]:
		var yoke := MeshInstance3D.new()
		yoke.name = item[0]
		var slab := BoxMesh.new()
		slab.size = item[1]
		yoke.mesh = slab
		yoke.material_override = item[3]
		yoke.position = head + item[2]
		cockpit.add_child(yoke)
	# the steering stem nut, sitting proud in the middle of the top yoke
	var stem := MeshInstance3D.new()
	stem.name = "SteeringStemNut"
	var stem_mesh := CylinderMesh.new()
	stem_mesh.top_radius = 0.09
	stem_mesh.bottom_radius = 0.09
	stem_mesh.height = 0.10
	stem.mesh = stem_mesh
	stem.material_override = steel
	stem.position = head + Vector3(0.0, 0.55, -0.16)
	cockpit.add_child(stem)
	# one clip-on per fork tube: a clamp round the tube, a bar swept back and in, a grip on the end and a lever perch
	for side in [-1.0, 1.0]:
		var tag := "Left" if side < 0.0 else "Right"
		var cap := MeshInstance3D.new()
		cap.name = "ForkCap" + tag
		var cap_mesh := CylinderMesh.new()
		cap_mesh.top_radius = 0.12
		cap_mesh.bottom_radius = 0.12
		cap_mesh.height = 0.08
		cap.mesh = cap_mesh
		cap.material_override = steel
		cap.position = head + Vector3(side * leg_x, 0.57, -0.14)
		cockpit.add_child(cap)
		var clamp := MeshInstance3D.new()
		clamp.name = "ClipOnClamp" + tag
		var clamp_mesh := CylinderMesh.new()
		clamp_mesh.top_radius = 0.16
		clamp_mesh.bottom_radius = 0.16
		clamp_mesh.height = 0.16
		clamp.mesh = clamp_mesh
		clamp.material_override = steel
		clamp.position = head + Vector3(side * leg_x, 0.26, -0.16)
		clamp.rotation.z = PI * 0.5 # a collar round the tube, so its bore runs across the bike
		cockpit.add_child(clamp)
		var bar := clip_on(host, head, side)
		var bar_start: Vector3 = bar[0]
		var bar_end: Vector3 = bar[1]
		var bar_dir: Vector3 = bar[2]
		var grip_from: Vector3 = bar[3]
		BikeChassis.add_member(cockpit, "ClipOn" + tag, bar_start, bar_end, BAR_RADIUS, steel)
		var grip_length := GRIP_LENGTH
		# the grip: rubber round the bar, the right one on a tube that twists with the throttle
		if side > 0.0:
			# the grip is held on the bar by an outer node lined up with the bar, and the tube inside it turns: twisting
			# the aligned node itself would throw its alignment away the moment the throttle moved
			var tube := Node3D.new()
			tube.name = "ThrottleGrip"
			tube.position = grip_from
			var up := Vector3.UP
			var x_axis := bar_dir.cross(up).normalized()
			tube.basis = Basis(x_axis, bar_dir, x_axis.cross(bar_dir).normalized())
			cockpit.add_child(tube)
			var twist := Node3D.new()
			twist.name = "ThrottleTube"
			tube.add_child(twist)
			var grip := MeshInstance3D.new()
			grip.name = "Grip"
			var grip_mesh := CylinderMesh.new()
			grip_mesh.top_radius = GRIP_RADIUS
			grip_mesh.bottom_radius = GRIP_RADIUS
			grip_mesh.height = grip_length
			grip.mesh = grip_mesh
			grip.material_override = rubber
			grip.position = Vector3(0.0, grip_length * 0.5, 0.0) # local Y is the bar axis
			twist.add_child(grip)
			# a raised rib, so the twist is readable instead of being an invisible rotation of a smooth cylinder
			var rib := MeshInstance3D.new()
			rib.name = "GripRib"
			var rib_mesh := BoxMesh.new()
			rib_mesh.size = Vector3(0.26, 0.04, 0.07)
			rib.mesh = rib_mesh
			rib.material_override = rubber
			rib.position = Vector3(0.0, grip_length * 0.85, 0.0)
			twist.add_child(rib)
			host._throttle_grip = twist
		else:
			var grip := MeshInstance3D.new()
			grip.name = "Grip"
			var grip_mesh := CylinderMesh.new()
			grip_mesh.top_radius = GRIP_RADIUS
			grip_mesh.bottom_radius = GRIP_RADIUS
			grip_mesh.height = grip_length
			grip.mesh = grip_mesh
			grip.material_override = rubber
			grip.position = (grip_from + bar_end) * 0.5
			grip.quaternion = Quaternion(Vector3.UP, bar_dir)
			cockpit.add_child(grip)
		# The perch and the lever. A lever runs ALONGSIDE the bar, from a pivot about 20 mm forward of the bar out towards
		# the end of the grip, and it swings back towards the bar when it is pulled - that is the movement a rider makes.
		var perch := Node3D.new()
		perch.name = "LeverPerch" + tag
		perch.position = grip_from - bar_dir * 0.12 + LEVER_PIVOT_OFFSET
		cockpit.add_child(perch)
		# the pivot bolt itself, so the lever visibly hangs off something
		var bolt := MeshInstance3D.new()
		bolt.name = "PivotBolt"
		var bolt_mesh := CylinderMesh.new()
		bolt_mesh.top_radius = 0.05
		bolt_mesh.bottom_radius = 0.05
		bolt_mesh.height = 0.12
		bolt.mesh = bolt_mesh
		bolt.material_override = steel
		bolt.position = perch.position
		cockpit.add_child(bolt)
		var pivot := Node3D.new()
		pivot.name = ("FrontBrakeLever" if side > 0.0 else "ClutchLever")
		pivot.position = perch.position
		cockpit.add_child(pivot)
		var blade_end: Vector3 = bar_dir * LEVER_LENGTH + Vector3(0.0, -0.02, 0.0)
		BikeChassis.add_member(pivot, "Blade", Vector3.ZERO, blade_end, 0.035, steel)
		BikeChassis.add_member(pivot, "Ball", blade_end, blade_end + bar_dir * 0.10, 0.06, steel)
		if side > 0.0:
			host._brake_lever = pivot
		else:
			host._clutch_lever = pivot


# A wheel spindle: a shaft through the hub, a nut on one end and the hollow bore showing at both ends. It is drawn at the
# axle height and across the bike, because that is the line the wheel actually turns on.
#   span  half the distance between the fork legs (or swingarm arms) it is clamped in
#   side  +1 puts the nut on the right-hand end, -1 on the left
