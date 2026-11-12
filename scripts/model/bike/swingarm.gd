class_name BikeSwingarm
extends RefCounted

# The rear swingarm, built as a casting rather than two sticks: each arm is a tapered box section (deep at the pivot where
# the bending load is, shallow at the axle), with a rib along its top, an axle block and chain adjuster at the end, a chain
# slider where the chain runs over the left arm, a pivot tube through the frame and a cross-brace behind the shock.
#
# Scene units: 1 unit = 100 mm. Every number here is ESTIMATE from a litre-class cast aluminium arm.
#
# The arms are added straight to `host` (the Chassis node) and keep the names Swingarm-1 / Swingarm1: the geometry test
# addresses them at those paths, and so does tools/diagnostics/render_swingarm.gd.

const PIVOT_WIDTH := 0.30 # section across the bike at the pivot
const PIVOT_HEIGHT := 0.48 # and its depth: a cast arm is deepest where it meets the frame
const AXLE_WIDTH := 0.24
const AXLE_HEIGHT := 0.26
const RIB_HEIGHT := 0.05
const PIVOT_TUBE_R := 0.16
const BRACE_R := 0.10
const BRACE_AT := 0.42 # where the cross-brace sits along the arm


static func build(host: Node3D, pivot: Vector3, rear: Vector3, rear_half: float, frame_half_width: float,
		steel: Material, dark: Material) -> void:
	for side in [-1.0, 1.0]:
		var tag := str(int(side))
		var from := Vector3(side * frame_half_width, pivot.y, pivot.z)
		var to := Vector3(side * (rear_half + 0.18), rear.y, rear.z)
		var arm := MeshInstance3D.new()
		arm.name = "Swingarm%s" % tag
		arm.mesh = _arm_mesh(from, to, PIVOT_WIDTH, PIVOT_HEIGHT, AXLE_WIDTH, AXLE_HEIGHT)
		arm.material_override = dark
		host.add_child(arm)

		# the rib along the top: a cast arm's stiffness shows as a raised spine, not a flat box
		var rib := MeshInstance3D.new()
		rib.name = "SwingarmRib%s" % tag
		rib.mesh = _arm_mesh(from + Vector3(0.0, PIVOT_HEIGHT * 0.5, 0.0),
			to + Vector3(0.0, AXLE_HEIGHT * 0.5, 0.0), PIVOT_WIDTH * 0.42, RIB_HEIGHT, AXLE_WIDTH * 0.42, RIB_HEIGHT)
		rib.material_override = dark
		host.add_child(rib)

		# the axle block the spindle passes through, and the adjuster that pulls it back
		var plate := MeshInstance3D.new()
		plate.name = "AxlePlate%s" % tag
		var plate_mesh := BoxMesh.new()
		plate_mesh.size = Vector3(AXLE_WIDTH * 1.05, AXLE_HEIGHT * 1.5, 0.34)
		plate.mesh = plate_mesh
		plate.position = to + Vector3(0.0, 0.0, 0.02)
		plate.material_override = steel
		host.add_child(plate)

		var adjuster := MeshInstance3D.new()
		adjuster.name = "AxleAdjuster%s" % tag
		var adjuster_mesh := BoxMesh.new()
		adjuster_mesh.size = Vector3(AXLE_WIDTH * 0.5, AXLE_HEIGHT * 0.35, 0.30)
		adjuster.mesh = adjuster_mesh
		adjuster.position = to + Vector3(0.0, AXLE_HEIGHT * 0.55, -0.20)
		adjuster.material_override = steel
		host.add_child(adjuster)

	# the chain runs over the left arm, so that is where the slider is
	var slider_at := pivot.lerp(rear, 0.34)
	var slider := MeshInstance3D.new()
	slider.name = "ChainSlider"
	var slider_mesh := BoxMesh.new()
	slider_mesh.size = Vector3(PIVOT_WIDTH * 0.55, 0.10, 0.62)
	slider.mesh = slider_mesh
	slider.position = Vector3(-(frame_half_width + (rear_half - frame_half_width) * 0.34),
		slider_at.y + PIVOT_HEIGHT * 0.5, slider_at.z)
	slider.material_override = steel
	host.add_child(slider)

	# the pivot tube through the frame, and the cross-brace behind the shock
	var pivot_tube := MeshInstance3D.new()
	pivot_tube.name = "SwingarmPivot"
	var tube_mesh := CylinderMesh.new()
	tube_mesh.top_radius = PIVOT_TUBE_R
	tube_mesh.bottom_radius = PIVOT_TUBE_R
	tube_mesh.height = (frame_half_width + 0.08) * 2.0
	tube_mesh.radial_segments = 16
	pivot_tube.mesh = tube_mesh
	pivot_tube.position = pivot
	pivot_tube.rotation.z = PI * 0.5 # the tube runs across the bike
	pivot_tube.material_override = steel
	host.add_child(pivot_tube)

	var brace_at := pivot.lerp(rear, BRACE_AT)
	var brace := MeshInstance3D.new()
	brace.name = "SwingarmBrace"
	var brace_mesh := CylinderMesh.new()
	brace_mesh.top_radius = BRACE_R
	brace_mesh.bottom_radius = BRACE_R
	brace_mesh.height = (rear_half + 0.18) * 2.0
	brace_mesh.radial_segments = 12
	brace.mesh = brace_mesh
	brace.position = Vector3(0.0, brace_at.y, brace_at.z)
	brace.rotation.z = PI * 0.5
	brace.material_override = dark
	host.add_child(brace)


# A tapered closed box section from one end to the other, with flat faces. Eight corners and six quads: a casting, not a
# cylinder, and the taper is what makes it read as one.
static func _arm_mesh(from: Vector3, to: Vector3, w0: float, h0: float, w1: float, h1: float) -> ArrayMesh:
	var corners := [
		Vector3(-w0 * 0.5, -h0 * 0.5, 0.0), Vector3(w0 * 0.5, -h0 * 0.5, 0.0),
		Vector3(w0 * 0.5, h0 * 0.5, 0.0), Vector3(-w0 * 0.5, h0 * 0.5, 0.0),
	]
	var far := [
		Vector3(-w1 * 0.5, -h1 * 0.5, 0.0), Vector3(w1 * 0.5, -h1 * 0.5, 0.0),
		Vector3(w1 * 0.5, h1 * 0.5, 0.0), Vector3(-w1 * 0.5, h1 * 0.5, 0.0),
	]
	var length := from.distance_to(to)
	var verts := PackedVector3Array()
	for c in corners:
		verts.append(from + c)
	for c in far:
		verts.append(from + (to - from).normalized() * length + c)
	# the four sides, then the two ends
	var faces := [[0, 1, 2], [0, 2, 3], [4, 6, 5], [4, 7, 6], [0, 5, 1], [0, 4, 5], [1, 6, 2], [1, 5, 6],
		[2, 7, 3], [2, 6, 7], [3, 4, 0], [3, 7, 4]]
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for f in faces:
		var a: Vector3 = verts[f[0]]
		var b: Vector3 = verts[f[1]]
		var c: Vector3 = verts[f[2]]
		var n := (b - a).cross(c - a).normalized()
		var base := verts.size()
		verts.append(a)
		verts.append(b)
		verts.append(c)
		for i in 3:
			normals.append(n)
		indices.append_array([base, base + 1, base + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
