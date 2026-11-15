class_name BikeAxles
extends RefCounted

# The wheel spindles: the shafts the wheels turn on, with nuts, washers and hollow bores.
# Every builder that adds nodes takes the node it draws into as `host`.

const AXLE_FRONT_RADIUS := 0.125 # 25 mm hollow front spindle, as a sport bike uses
const AXLE_REAR_RADIUS := 0.14 # 28 mm rear axle


static func add_axle(parent: Node3D, at: Vector3, span: float, radius: float, steel: Material, dark: Material, side: float, name_prefix: String = "") -> void:
	var tag := name_prefix if not name_prefix.is_empty() else ("Front" if at.z > 0.0 else "Rear")
	var shaft := MeshInstance3D.new()
	shaft.name = tag + "Axle"
	var shape := CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = span * 2.0
	shaft.mesh = shape
	shaft.material_override = steel
	shaft.position = at
	shaft.rotation.z = PI * 0.5 # a cylinder stands on Y: lay it across the bike
	parent.add_child(shaft)
	# the bore, so it reads as a hollow spindle rather than a solid rod: a dark disc sunk into each end
	for end in [-1.0, 1.0]:
		var bore := MeshInstance3D.new()
		bore.name = "%sAxleBore%d" % [tag, 1 if end > 0.0 else 0]
		var hole := CylinderMesh.new()
		hole.top_radius = radius * 0.55
		hole.bottom_radius = radius * 0.55
		hole.height = 0.01
		bore.mesh = hole
		bore.material_override = dark
		bore.position = at + Vector3(end * (span - 0.004), 0.0, 0.0)
		bore.rotation.z = PI * 0.5
		parent.add_child(bore)
	# the nut that holds it in, on one end only: the other end is the bolt head or the fork's clamp
	var nut := MeshInstance3D.new()
	nut.name = tag + "AxleNut"
	var nut_shape := CylinderMesh.new()
	nut_shape.top_radius = radius * 1.6
	nut_shape.bottom_radius = radius * 1.6
	nut_shape.height = 0.10
	nut.mesh = nut_shape
	nut.material_override = steel
	nut.position = at + Vector3(side * (span + 0.05), 0.0, 0.0)
	nut.rotation.z = PI * 0.5
	parent.add_child(nut)
	# the washer under it, so the nut is not sitting on nothing
	var washer := MeshInstance3D.new()
	washer.name = tag + "AxleWasher"
	var washer_shape := CylinderMesh.new()
	washer_shape.top_radius = radius * 1.8
	washer_shape.bottom_radius = radius * 1.8
	washer_shape.height = 0.012
	washer.mesh = washer_shape
	washer.material_override = dark
	washer.position = at + Vector3(side * (span + 0.005), 0.0, 0.0)
	washer.rotation.z = PI * 0.5
	parent.add_child(washer)


# The front brake master cylinder: a radial unit clamped to the right clip-on. A 19 mm bore body, a two-bolt clamp round
# the bar, the banjo the hose screws into, the lever pivot 20 mm off the bar (Brembo RCS19 runs 18-20 mm), and the fluid
# reservoir standing on its own bracket with a feed hose down to the body.
#   bar  [start, end, direction, grip_from] from BikeCockpit.clip_on(host, )
