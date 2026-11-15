class_name BikeSwingarm
extends RefCounted

# The rear swingarm, modelled as a cast arm rather than a stick from the frame rail to the axle.
#
# A real arm does four things this has to reflect:
#   1. it hangs from a pivot boss inside the frame, narrower than the tyre, so it starts INBOARD of the wheel;
#   2. it splays outward immediately, clearing the tyre before it reaches the tyre's front edge;
#   3. from the elbow it runs straight to the axle along the chain line, tapering as the bending load falls away;
#   4. the two arms are tied by a torsion box behind the shock, and end in an axle block with a chain adjuster.
#
# The section is swept along a three-point path (pivot -> elbow -> axle), so the arm bends where a real one does, and each
# ring is tapered: deep at the pivot, shallow at the axle. Scene units, 1 unit = 100 mm; proportions are ESTIMATE.
#
# The arms are added straight to `host` (the Chassis node) under the names Swingarm-1 / Swingarm1: tests and
# tools/diagnostics/render_swingarm.gd address them at those paths.

const PIVOT_W := 0.30 # section across the bike at the pivot
const PIVOT_H := 0.46 # and its depth: a cast arm is deepest where it meets the frame
const ELBOW_W := 0.26
const ELBOW_H := 0.34
const AXLE_W := 0.24
const AXLE_H := 0.26
const ELBOW_AT := 0.34 # where along the arm it stops splaying out and runs straight
const AXLE_SETBACK := 0.18 # the arm's centreline sits this far outboard of the tyre's half width
const BRACE_AT := 0.42
const BRACE_H := 0.24
const BRACE_W := 0.18


static func build(host: Node3D, pivot: Vector3, rear: Vector3, rear_half: float, frame_half_width: float,
		steel: Material, dark: Material) -> void:
	for side in [-1.0, 1.0]:
		var tag := str(int(side))
		var start := Vector3(side * (frame_half_width - 0.06), pivot.y, pivot.z) # inside the frame, not on its skin
		var axle_x: float = side * (rear_half + AXLE_SETBACK)
		var elbow := Vector3(axle_x, pivot.y - 0.06, lerpf(pivot.z, rear.z, ELBOW_AT))
		var end := Vector3(axle_x, rear.y, rear.z)

		var arm := MeshInstance3D.new()
		arm.name = "Swingarm%s" % tag
		arm.mesh = _swept_arm([start, elbow, end], [Vector2(PIVOT_W, PIVOT_H), Vector2(ELBOW_W, ELBOW_H),
			Vector2(AXLE_W, AXLE_H)])
		arm.material_override = dark
		host.add_child(arm)

		# the pivot boss: the arm is a casting round a bearing, not a cut-off box
		var boss := MeshInstance3D.new()
		boss.name = "SwingarmBoss%s" % tag
		var boss_mesh := CylinderMesh.new()
		boss_mesh.top_radius = PIVOT_H * 0.42
		boss_mesh.bottom_radius = PIVOT_H * 0.42
		boss_mesh.height = PIVOT_W * 1.08
		boss_mesh.radial_segments = 20
		boss.mesh = boss_mesh
		boss.position = start
		boss.rotation.z = PI * 0.5
		boss.material_override = dark
		host.add_child(boss)

		# rounded axle end: a real arm closes round the spindle housing
		var housing := MeshInstance3D.new()
		housing.name = "AxleHousing%s" % tag
		var housing_mesh := CylinderMesh.new()
		housing_mesh.top_radius = AXLE_H * 0.56
		housing_mesh.bottom_radius = AXLE_H * 0.56
		housing_mesh.height = AXLE_W * 1.04
		housing_mesh.radial_segments = 20
		housing.mesh = housing_mesh
		housing.position = end
		housing.rotation.z = PI * 0.5
		housing.material_override = steel
		host.add_child(housing)

		var plate := MeshInstance3D.new()
		plate.name = "AxlePlate%s" % tag
		var plate_mesh := BoxMesh.new()
		plate_mesh.size = Vector3(AXLE_W * 0.96, AXLE_H * 1.35, 0.36)
		plate.mesh = plate_mesh
		plate.position = end + Vector3(0.0, -0.02, -0.10)
		plate.material_override = steel
		host.add_child(plate)

		var adjuster := MeshInstance3D.new()
		adjuster.name = "AxleAdjuster%s" % tag
		var adjuster_mesh := BoxMesh.new()
		adjuster_mesh.size = Vector3(AXLE_W * 0.5, AXLE_H * 0.3, 0.34)
		adjuster.mesh = adjuster_mesh
		adjuster.position = end + Vector3(0.0, AXLE_H * 0.52, -0.26)
		adjuster.material_override = steel
		host.add_child(adjuster)

	# the chain runs over the left arm, so the slider goes there, over the elbow
	var slider_at := pivot.lerp(rear, 0.30)
	var slider := MeshInstance3D.new()
	slider.name = "ChainSlider"
	var slider_mesh := BoxMesh.new()
	slider_mesh.size = Vector3(0.14, 0.09, 0.70)
	slider.mesh = slider_mesh
	slider.position = Vector3(-(rear_half + AXLE_SETBACK), slider_at.y + PIVOT_H * 0.42, slider_at.z)
	slider.material_override = steel
	host.add_child(slider)

	# pivot tube through the frame
	var pivot_tube := MeshInstance3D.new()
	pivot_tube.name = "SwingarmPivot"
	var tube_mesh := CylinderMesh.new()
	tube_mesh.top_radius = PIVOT_H * 0.34
	tube_mesh.bottom_radius = PIVOT_H * 0.34
	tube_mesh.height = (frame_half_width - 0.06) * 2.0
	tube_mesh.radial_segments = 18
	pivot_tube.mesh = tube_mesh
	pivot_tube.position = pivot
	pivot_tube.rotation.z = PI * 0.5
	pivot_tube.material_override = steel
	host.add_child(pivot_tube)

	# the torsion box behind the shock: a box section, not a rod, because that is what resists the twist
	var brace_at := pivot.lerp(rear, BRACE_AT)
	var brace := MeshInstance3D.new()
	brace.name = "SwingarmBrace"
	var brace_mesh := BoxMesh.new()
	brace_mesh.size = Vector3((rear_half + AXLE_SETBACK) * 2.0, BRACE_H, BRACE_W)
	brace.mesh = brace_mesh
	brace.position = Vector3(0.0, brace_at.y - ELBOW_H * 0.1, brace_at.z)
	brace.material_override = dark
	host.add_child(brace)


# Sweeps a tapered rectangular section along a polyline. Each ring is perpendicular to the path, so the arm bends like a
# real one instead of shearing along z, and the section is interpolated between the stations given.
static func _swept_arm(path: Array, sections: Array) -> ArrayMesh:
	var points := PackedVector3Array()
	for p in path:
		points.append(p)
	var rings := []
	for i in points.size():
		var tangent: Vector3
		if i == 0:
			tangent = (points[1] - points[0]).normalized()
		elif i == points.size() - 1:
			tangent = (points[i] - points[i - 1]).normalized()
		else:
			tangent = ((points[i + 1] - points[i]).normalized() + (points[i] - points[i - 1]).normalized()).normalized()
		var up := Vector3.UP - tangent * tangent.dot(Vector3.UP)
		up = up.normalized() if up.length() > 1e-4 else Vector3.FORWARD
		var side := tangent.cross(up).normalized()
		var w: float = sections[i].x
		var h: float = sections[i].y
		rings.append([
			points[i] - side * w * 0.5 - up * h * 0.5,
			points[i] + side * w * 0.5 - up * h * 0.5,
			points[i] + side * w * 0.5 + up * h * 0.5,
			points[i] - side * w * 0.5 + up * h * 0.5,
		])
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for i in rings.size() - 1:
		var a: Array = rings[i]
		var b: Array = rings[i + 1]
		for k in 4:
			var k2 := (k + 1) % 4
			_add_quad(verts, normals, indices, a[k], a[k2], b[k2], b[k])
	_add_quad(verts, normals, indices, rings[0][3], rings[0][2], rings[0][1], rings[0][0])
	var last: Array = rings[rings.size() - 1]
	_add_quad(verts, normals, indices, last[0], last[1], last[2], last[3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _add_quad(verts: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array,
		p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3) -> void:
	var n := (p1 - p0).cross(p2 - p0).normalized()
	var base := verts.size()
	for p in [p0, p1, p2, p0, p2, p3]:
		verts.append(p)
		normals.append(n)
		indices.append(verts.size() - 1)
	base += 0
