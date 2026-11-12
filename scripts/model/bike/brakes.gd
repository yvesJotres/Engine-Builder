class_name BikeBrakes
extends RefCounted

# The hydraulic hardware: discs with their carriers and ABS tone rings, radial calipers, master cylinders and lines.
# Every builder that adds nodes takes the node it draws into as `host`.

const ROTOR_THICKNESS := BikeMeshes.ROTOR_THICKNESS # the disc itself is drawn by the mesh module
const ROTOR_INNER := BikeMeshes.ROTOR_INNER
const TONE_RING_WINDOW_LO := BikeMeshes.TONE_RING_WINDOW_LO
const TONE_RING_WINDOW_HI := BikeMeshes.TONE_RING_WINDOW_HI
const FORK_LEG_OFFSET := BikeChassis.FORK_LEG_OFFSET
const LEVER_PIVOT_OFFSET := BikeCockpit.LEVER_PIVOT_OFFSET
const FRONT_DISC_RADIUS := 1.65 # 330 mm
const REAR_DISC_RADIUS := 1.10 # 220 mm
const CALIPER_ANGLE_DEG := 150.0 # trailing side of the fork leg, a little above the axle: where production bikes mount them
const TONE_RING_THICKNESS := 0.020 # scene units, 2 mm: the ABS sensor ring bolted to the carrier
const TONE_RING_TEETH := 48 # slots, so 48 pulses per wheel revolution (a real reluctor ring uses 44-52)
const TONE_RING_INNER := 0.34 # ring band, as a share of the disc radius
const TONE_RING_OUTER := 0.60
const TONE_RING_READ_SHARE := TONE_RING_INNER + (TONE_RING_OUTER - TONE_RING_INNER) * (TONE_RING_WINDOW_LO + TONE_RING_WINDOW_HI) * 0.5
const CARRIER_THICKNESS := 0.055 # scene units, 5.5 mm: the aluminium plate between hub and friction ring
const CARRIER_OFFSET := 0.025 # scene units: the carrier sits this far inboard of the disc plane


static func add_brake_rotor(wheel: Node3D, x: float, radius: float, material: Material, dark: Material, has_abs: bool, rotor_scene: PackedScene = null, suffix: String = "") -> void:
	var rotor := MeshInstance3D.new()
	rotor.name = "BrakeRotor" + suffix
	rotor.mesh = BikeMeshes.rotor_mesh(radius)
	var rotor_material := material.duplicate() as StandardMaterial3D
	rotor_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	rotor_material.metallic = 0.6
	rotor.material_override = rotor_material
	rotor.position.x = x
	wheel.add_child(rotor)
	# the edges that make it a disc: without them the two perforated faces are separate sheets with nothing between
	# them, which is what a pair of flat discs glued back to back looks like
	var outer_edge := MeshInstance3D.new()
	outer_edge.name = "RotorEdgeOuter" + suffix
	outer_edge.mesh = BikeMeshes.band_mesh(radius, ROTOR_THICKNESS, 1.0)
	outer_edge.material_override = rotor_material
	rotor.add_child(outer_edge)
	var inner_edge := MeshInstance3D.new()
	inner_edge.name = "RotorEdgeInner" + suffix
	inner_edge.mesh = BikeMeshes.band_mesh(radius * ROTOR_INNER, ROTOR_THICKNESS, -1.0)
	inner_edge.material_override = rotor_material
	rotor.add_child(inner_edge)
	var carrier := MeshInstance3D.new()
	carrier.name = "RotorCarrier" + suffix
	carrier.mesh = BikeMeshes.carrier_mesh(radius * 0.28, radius * 0.70, CARRIER_THICKNESS, 6)
	# the carrier is a plate too: close its inner and outer rims, or it is another pair of flat sheets
	for edge in [[radius * 0.70, 1.0, "CarrierEdgeOuter"], [radius * 0.28, -1.0, "CarrierEdgeInner"]]:
		var band := MeshInstance3D.new()
		band.name = str(edge[2]) + suffix
		band.mesh = BikeMeshes.band_mesh(edge[0], CARRIER_THICKNESS, edge[1])
		band.material_override = dark
		carrier.add_child(band)
	var carrier_material := dark.duplicate() as StandardMaterial3D
	carrier_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	carrier.material_override = carrier_material
	carrier.position.x = x + CARRIER_OFFSET
	wheel.add_child(carrier)
	for i in 6:
		var angle := TAU * i / 6.0
		BikeChassis.add_member(wheel, "RotorBolt%d%s" % [i, suffix], Vector3(x - 0.035, radius * 0.58 * cos(angle), radius * 0.58 * sin(angle)), Vector3(x + 0.055, radius * 0.58 * cos(angle), radius * 0.58 * sin(angle)), 0.045, material)
	var authored := rotor_scene.instantiate() if rotor_scene != null else null
	if authored is Node3D:
		authored.name = "AuthoredRotor"
		authored.position.x = x
		wheel.add_child(authored)
		rotor.visible = false
		carrier.visible = false
		for i in 6:
			wheel.get_node("RotorBolt%d%s" % [i, suffix]).visible = false
	elif authored != null:
		authored.free()
		push_warning("Rotor scene must have a Node3D root")
	if has_abs:
		# An ABS disc carries the sensor's target ring: a toothed steel ring bolted to the carrier face, a real part with
		# its own thickness and walls. Mounted on the carrier, so it turns with the wheel and disappears with an authored
		# rotor exactly as the carrier does.
		var tone := MeshInstance3D.new()
		tone.name = "ABSToneRing" + suffix
		tone.mesh = BikeMeshes.tone_ring_mesh(radius * TONE_RING_INNER, radius * TONE_RING_OUTER, TONE_RING_THICKNESS, TONE_RING_TEETH)
		tone.material_override = rotor_material
		# on the outboard face of the carrier, the side the fork leg and its pickup are on: a ring on the inboard face
		# would be hidden behind the disc, where no sensor could ever read it
		# only the outboard disc (negative x) is ever given a ring, so "towards -x" is the face the pickup reads
		tone.position.x = -(CARRIER_THICKNESS * 0.5 + TONE_RING_THICKNESS * 0.5)
		carrier.add_child(tone)


# The hydraulic layout: calipers, master cylinders, reservoirs and lines. Nothing here turns with the wheel - the discs
# do, and the calipers hang off the fork legs or the rear bracket, straddling the disc.


static func build_brakes(host: Node3D, rear: Vector3, front: Vector3, countershaft: Vector3, half_width: float, has_abs: bool, steel: Material, dark: Material) -> void:
	var brakes := Node3D.new()
	brakes.name = "BrakeHardware"
	host.add_child(brakes)
	# one radial caliper per front disc, plus one at the back. A radial caliper's bolts run parallel to the fork leg and
	# it straddles the disc, so it is built at the disc's edge and clamped over it.
	add_radial_caliper(brakes, "FrontCaliper", front + Vector3(-(host._front_half + 0.06), 0.0, 0.0), FRONT_DISC_RADIUS, -1.0, steel, dark)
	add_radial_caliper(brakes, "FrontCaliperRight", front + Vector3(host._front_half + 0.06, 0.0, 0.0), FRONT_DISC_RADIUS, 1.0, steel, dark)
	var rear_caliper_pos: Vector3 = rear + Vector3(-(host._rear_half + 0.06), 0.0, 0.0)
	add_radial_caliper(brakes, "RearCaliper", rear_caliper_pos, REAR_DISC_RADIUS, -1.0, steel, dark, false)
	# the rear caliper hangs on a bracket that slides on the axle, and a torque arm stops it turning: without it the
	# caliper would rotate with the disc
	var rear_caliper_node := brakes.get_node("RearCaliper") as Node3D
	var arm_from: Vector3 = rear_caliper_node.position + Vector3(0.0, -0.1, 0.1)
	BikeChassis.add_member(brakes, "RearTorqueArm", arm_from, arm_from + Vector3(0.0, 0.55, -0.75), 0.06, steel)
	BikeChassis.add_member(brakes, "RearCaliperBracket", rear_caliper_pos + Vector3(0.10, 0.0, 0.0), rear + Vector3(0.16, 0.0, 0.0), 0.05, dark)
	var head := front + Vector3(0.0, 4.0, -1.1)
	# master cylinders: one on the clip-on for the front, one above the pedal for the rear, each with its own reservoir
	# the front master cylinder clamps to the right clip-on at the lever perch, with its reservoir standing above it:
	# a reservoir buried inside the master body is invisible, and a master floating off the bar is worse
	var right_bar := BikeCockpit.clip_on(host, head, 1.0)
	var front_master: Vector3 = (right_bar[3] as Vector3) - (right_bar[2] as Vector3) * 0.12
	var front_reservoir := front_master + Vector3(0.0, 0.34, 0.0)
	var rear_master := countershaft + Vector3(-half_width - 0.18, 0.05, -1.15)
	var reservoir_mat := BikeMaterials.make(Color(0.72, 0.69, 0.55), 0.55)
	add_front_master(brakes, right_bar, steel, dark, reservoir_mat)
	add_master_cylinder(brakes, "RearMasterCylinder", rear_master, steel)
	for item in [["RearReservoir", rear_master + Vector3(0, 0.45, 0)]]:
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
		BikeChassis.add_member(brakes, "%sCap" % item[0], item[1] + Vector3(0, 0.12, 0), item[1] + Vector3(0, 0.16, 0), 0.14, dark)
	BikeChassis.add_member(brakes, "RearReservoirHose", rear_master, rear_master + Vector3(0, 0.34, 0), 0.025, dark)
	# the line runs down the fork leg to the caliper banjo: a real hose follows the leg, it does not cut across the wheel
	var fork_top: Vector3 = front + Vector3(-(host._front_half + FORK_LEG_OFFSET + 0.02), 2.7, -0.30)
	var fork_mid: Vector3 = front + Vector3(-(host._front_half + FORK_LEG_OFFSET), 1.1, -0.16)
	var front_caliper: Vector3 = (brakes.get_node("FrontCaliper") as Node3D).position + Vector3(0.0, 0.16, 0.0)
	var rear_caliper: Vector3 = (brakes.get_node("RearCaliper") as Node3D).position + Vector3(0.0, 0.12, 0.0)
	if has_abs:
		# the ring sits on the outboard face of the carrier, so the pickup's tip is placed from that face, not from the
		# disc plane: it has to stop a fraction of a millimetre short of the steel and read over the toothed band
		var ring_face := -(CARRIER_THICKNESS + TONE_RING_THICKNESS) * 0.5 + CARRIER_OFFSET
		for item in [["FrontABSSensor", front, host._front_half + 0.06, FRONT_DISC_RADIUS], ["RearABSSensor", rear, host._rear_half + 0.06, REAR_DISC_RADIUS]]:
			var sensor_pos: Vector3 = item[1] + Vector3(-(float(item[2])) + ring_face - 0.007, float(item[3]) * TONE_RING_READ_SHARE, 0.0)
			BikeChassis.add_member(brakes, item[0], sensor_pos + Vector3(-0.22, 0.08, 0), sensor_pos, 0.055, dark)
		var module_pos := countershaft + Vector3(-half_width - 0.10, 0.65, -0.65)
		var module := MeshInstance3D.new()
		module.name = "ABSModule"
		var block := BoxMesh.new()
		block.size = Vector3(0.32, 0.36, 0.45)
		module.mesh = block
		module.material_override = steel
		module.position = module_pos
		brakes.add_child(module)
		hose(brakes, "FrontFeed", [front_master, fork_top, module_pos], dark)
		hose(brakes, "FrontBrakeHose", [module_pos, fork_top, fork_mid, front_caliper], dark)
		hose(brakes, "RearFeed", [rear_master, module_pos], dark)
		hose(brakes, "RearBrakeHose", [module_pos, rear_caliper], dark)
	else:
		hose(brakes, "FrontBrakeHose", [front_master, fork_top, fork_mid, front_caliper], dark)
		hose(brakes, "RearBrakeHose", [rear_master, rear_caliper], dark)


# A radial-mount caliper: two halves clamped either side of the disc, a bridge over its edge, and a mounting ear that
# reaches the fork leg (or the rear bracket). The whole thing is built in a frame whose X is the axle, Y points out from
# the axle and Z runs along the disc, so it can be placed on any disc by angle alone.
#   disc_centre  centre of the disc it clamps
#   disc_radius  radius of the disc, so the body sits on its edge
#   side         -1 for the left-hand disc (mount ear towards -x), +1 for the right


static func add_radial_caliper(parent: Node3D, caliper_name: String, disc_centre: Vector3, disc_radius: float, side: float,
		steel: Material, dark: Material, four_piston: bool = true) -> void:
	var angle := deg_to_rad(CALIPER_ANGLE_DEG)
	var radial := Vector3(0.0, sin(angle), cos(angle)) # trailing side, a little above the axle
	var axial := Vector3(1.0, 0.0, 0.0) # the disc's normal
	var mount := Node3D.new()
	mount.name = caliper_name
	mount.basis = Basis(axial, radial, axial.cross(radial))
	mount.position = disc_centre + radial * disc_radius
	parent.add_child(mount)
	# a four-piston radial caliper is a long body; the single-piston rear is shorter and narrower
	var body := Vector3(0.19, 0.58, 0.95) if four_piston else Vector3(0.15, 0.40, 0.62)
	var clearance := ROTOR_THICKNESS * 0.5 + 0.012 # the gap either side of the disc the pads live in
	for half in [-1.0, 1.0]:
		var piece := MeshInstance3D.new()
		piece.name = "Half%d" % (1 if half > 0.0 else 0)
		var shape := BoxMesh.new()
		shape.size = body
		piece.mesh = shape
		piece.material_override = steel
		piece.position = Vector3(half * (body.x * 0.5 + clearance), 0.0, 0.0)
		mount.add_child(piece)
	# the bridge that joins the two halves over the disc's edge: without it the halves read as separate blocks
	var bridge := MeshInstance3D.new()
	bridge.name = "Bridge"
	var shape_bridge := BoxMesh.new()
	shape_bridge.size = Vector3(body.x * 2.0 + clearance * 2.0, 0.13, body.z * 0.92)
	bridge.mesh = shape_bridge
	bridge.material_override = dark
	bridge.position = Vector3(0.0, body.y * 0.5 - 0.065, 0.0)
	mount.add_child(bridge)
	# the mounting ear, reaching out to the leg or bracket: radial calipers bolt straight into lugs on the fork
	var ear := MeshInstance3D.new()
	ear.name = "Mount"
	var shape_ear := BoxMesh.new()
	shape_ear.size = Vector3(0.26, 0.30, 0.34)
	ear.mesh = shape_ear
	ear.material_override = dark
	ear.position = Vector3(side * (body.x * 0.5 + clearance + 0.10), -0.06, 0.0)
	mount.add_child(ear)


# Where a clip-on runs: from the clamp on the fork tube back to where the rider's hand goes. The cockpit builds the bar and
# the grips from these points, and the brake hardware clamps the master cylinder to the same bar, so they share the maths.


static func add_front_master(parent: Node3D, bar: Array, steel: Material, dark: Material, glass: Material) -> void:
	var dir: Vector3 = bar[2]
	var on_bar: Vector3 = (bar[3] as Vector3) - dir * 0.30
	var pivot: Vector3 = on_bar + LEVER_PIVOT_OFFSET
	# the body: bore, piston housing and the banjo boss, all lying along the bar
	add_tube(parent, "FrontMasterCylinder", on_bar, dir, 0.10, 0.85, steel)
	add_tube(parent, "FrontMasterPiston", on_bar + dir * 0.38, dir, 0.11, 0.20, dark)
	add_tube(parent, "FrontMasterClamp", on_bar - dir * 0.40, dir, 0.15, 0.16, steel)
	# the banjo, pointing down out of the body: this is where the brake line arrives
	var banjo := Vector3(0.0, -0.16, 0.0)
	BikeChassis.add_member(parent, "FrontMasterBanjo", on_bar + dir * 0.10, on_bar + dir * 0.10 + banjo, 0.06, steel)
	# the lever pivot bolt, 20 mm forward of the bar
	BikeChassis.add_member(parent, "FrontMasterPivot", on_bar, pivot, 0.045, steel)
	# the reservoir, standing clear on its bracket with a feed hose down to the cylinder
	var cup := on_bar + Vector3(0.0, 0.34, 0.06)
	var reservoir := MeshInstance3D.new()
	reservoir.name = "FrontReservoir"
	var shape := CylinderMesh.new()
	shape.top_radius = 0.12
	shape.bottom_radius = 0.11
	shape.height = 0.26
	reservoir.mesh = shape
	reservoir.material_override = glass
	reservoir.position = cup
	parent.add_child(reservoir)
	BikeChassis.add_member(parent, "FrontReservoirCap", cup + Vector3(0, 0.13, 0), cup + Vector3(0, 0.17, 0), 0.13, dark)
	BikeChassis.add_member(parent, "FrontReservoirBracket", on_bar + Vector3(0.0, 0.08, 0.0), cup + Vector3(0.0, -0.12, 0.0), 0.035, dark)
	BikeChassis.add_member(parent, "FrontReservoirHose", cup + Vector3(0.0, -0.13, 0.0), on_bar + Vector3(0.0, 0.09, 0.0), 0.03, dark)


# A cylinder of the given radius and length, laid along dir and centred on at.


static func add_master_cylinder(parent: Node3D, master_name: String, at: Vector3, steel: Material) -> void:
	var master := MeshInstance3D.new()
	master.name = master_name
	var shape := CylinderMesh.new()
	shape.top_radius = 0.10
	shape.bottom_radius = 0.10
	shape.height = 0.34
	master.mesh = shape
	master.material_override = steel
	master.position = at
	master.rotation_degrees = Vector3(0.0, 0.0, 90.0) # the bore lies along the bar, as on a bike
	parent.add_child(master)


static func add_tube(parent: Node3D, tube_name: String, at: Vector3, dir: Vector3, radius: float, length: float, material: Material) -> void:
	var tube := MeshInstance3D.new()
	tube.name = tube_name
	var shape := CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = length
	tube.mesh = shape
	tube.material_override = material
	tube.position = at
	tube.quaternion = Quaternion(Vector3.UP, dir.normalized())
	parent.add_child(tube)


# A master cylinder: a body with a cap and a piston rod. A real one is a bore with a reservoir on top and a lever or a
# pedal pushing the piston - this is the drawn stand-in for that, sized to sit on a clip-on or above the rear pedal.


static func hose(parent: Node3D, hose_name: String, points: Array, material: Material) -> void:
	for i in points.size() - 1:
		BikeChassis.add_member(parent, "%s%d" % [hose_name, i], points[i], points[i + 1], 0.025, material)


# The two perforated faces of the friction ring. The edge bands that close them into a solid are _band_mesh.
