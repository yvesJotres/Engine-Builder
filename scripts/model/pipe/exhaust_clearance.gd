class_name ExhaustClearance
extends RefCounted

# Does the exhaust pass through the bike? Every pipe is sampled along its centreline as a sphere of its own radius; the
# bike's frame members are capsules (every structural part is a cylinder), the engine and the tank are boxes (their
# bounding boxes) and the wheels are discs. A sample whose sphere overlaps one of those is a clip.
#
# It lives here rather than in a test so the diagnostic tool and the unit test measure the same thing: tools/diagnostics/
# exhaust_clearance.gd prints the numbers, tests/unit/model/pipe/exhaust_clearance_test.gd fails the build when they
# appear.
#
# Deliberately coarse where the model is coarse: the engine is an AABB, so a pipe leaving a port sits ON the box rather
# than inside the casting. Only a sample whose skin is genuinely buried under the box surface counts, i.e. depth beyond
# the pipe's own radius. A pipe touching a frame tube by a couple of millimetres counts as a clip, because that is not
# where anyone routes an exhaust.

const SAMPLE_STEP := 0.04
const PORT_STUB := 0.30 # a primary starts on its own port, on the engine's surface; that stub is not a clip


# Returns {"worst": {obstacle: penetration_units}, "samples": count}. Empty "worst" means the exhaust is clear.
static func check(drivetrain: Node3D, engine_bounds: AABB, tank_bounds: AABB, layout: ExhaustLayout,
		tolerance := 0.02) -> Dictionary:
	var capsules := _capsules(drivetrain)
	var discs := _discs(drivetrain)
	var worst := {}
	var hits := 0
	for pipe in layout.pipes:
		var pts: PackedVector3Array = pipe.pts
		var radii: PackedFloat32Array = pipe.radii
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var radius: float = radii[mini(i + 1, radii.size() - 1)]
			var steps := maxi(1, int(a.distance_to(b) / SAMPLE_STEP))
			for s in steps + 1:
				var p := a.lerp(b, float(s) / float(steps))
				var at_port: bool = pipe.kind == "primary" and p.distance_to(pts[0]) < PORT_STUB
				for cap in capsules:
					var d := _point_segment(p, cap["a"], cap["b"])
					var pen: float = radius + float(cap["radius"]) - d
					if pen > tolerance:
						hits += 1
						_note(worst, "%s -> %s" % [pipe.name, cap["name"]], pen)
				if not at_port:
					for label in [["engine", engine_bounds], ["tank", tank_bounds]]:
						var box: AABB = label[1]
						if box.size == Vector3.ZERO:
							continue
						var pen := -_box_signed_distance(p, box) - radius
						if pen > tolerance:
							hits += 1
							_note(worst, "%s -> %s" % [pipe.name, label[0]], pen)
				for disc in discs:
					var dx: float = absf(p.x - disc["centre"].x)
					var radial: float = Vector2(p.y - disc["centre"].y, p.z - disc["centre"].z).length()
					var out: float = maxf(0.0, radial - float(disc["outer"]))
					var side: float = maxf(0.0, dx - float(disc["half_width"]))
					var pen: float = radius - Vector2(out, side).length()
					if pen > tolerance:
						hits += 1
						_note(worst, "%s -> tyre:%s" % [pipe.name, disc["name"]], pen)
	return {"worst": worst, "samples": hits}


# Every cylinder on the bike, as a capsule: the frame rails, the fork, the swingarm, the axles, the hoses.
static func _capsules(drivetrain: Node3D) -> Array:
	var out := []
	for node in drivetrain.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if not (mi.mesh is CylinderMesh):
			continue
		var shape := mi.mesh as CylinderMesh
		var axis: Vector3 = (mi.global_transform.basis * Vector3.UP).normalized()
		var half: float = shape.height * 0.5
		out.append({"name": str(mi.name), "a": mi.global_position - axis * half,
			"b": mi.global_position + axis * half, "radius": shape.top_radius})
	return out


# The two wheels as discs: a tyre is a torus on the x axis, so what matters is its outer radius and how wide it is.
static func _discs(drivetrain: Node3D) -> Array:
	var out := []
	for wheel in [drivetrain.get("_front_wheel"), drivetrain.get("_wheel_pivot")]:
		if wheel == null or not (wheel is Node3D):
			continue
		var tyre := (wheel as Node3D).get_node_or_null("Tyre") as MeshInstance3D
		if tyre == null or not (tyre.mesh is TorusMesh):
			continue
		var torus := tyre.mesh as TorusMesh
		var width: float = tyre.mesh.get_aabb().size.y * absf(tyre.scale.y) # the torus is only scaled across its axis
		out.append({"name": str((wheel as Node3D).name), "centre": tyre.global_position,
			"outer": torus.outer_radius, "half_width": width * 0.5})
	return out


static func _note(worst: Dictionary, key: String, pen: float) -> void:
	if not worst.has(key) or pen > worst[key]:
		worst[key] = pen


static func _point_segment(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var denom := ab.dot(ab)
	if denom < 1e-12:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / denom, 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func _box_signed_distance(p: Vector3, box: AABB) -> float:
	var centre := box.get_center()
	var half := box.size * 0.5
	var q := Vector3(absf(p.x - centre.x) - half.x, absf(p.y - centre.y) - half.y, absf(p.z - centre.z) - half.z)
	var outside := Vector3(maxf(q.x, 0.0), maxf(q.y, 0.0), maxf(q.z, 0.0)).length()
	var inside: float = minf(maxf(q.x, maxf(q.y, q.z)), 0.0)
	return outside + inside
