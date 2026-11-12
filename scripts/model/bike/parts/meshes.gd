class_name BikeMeshes
extends RefCounted

# Mesh generators for the bike: brake discs with their carriers, the pierced ABS tone ring, and the edge bands that
# close a flat disc into steel. Pure maths on numbers - nothing here touches a node.
# Every builder that adds nodes takes the node it draws into as `host`.

const ROTOR_THICKNESS := 0.050 # scene units, 5 mm of steel: a motorcycle disc is 4-5.5 mm, and it is one piece, not a pair of sheets
const ROTOR_INNER := 0.70 # the friction ring starts here, in rotor radii
const TONE_RING_WINDOW_LO := 0.16 # the windows span this far into the band, leaving a solid rim on each side
const TONE_RING_WINDOW_HI := 0.84
const TONE_RING_DUTY := 0.52 # share of the pitch that is open window; the rest is the tooth the pickup counts


static func rotor_mesh(radius: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var face := ROTOR_THICKNESS * 0.5
	# Each sector is a curved quadrilateral with an eight-sided through-hole.
	for segment in 32:
		var mid := TAU * (segment + 0.5) / 32.0
		var half := TAU / 64.0
		var perimeter := [Vector2(ROTOR_INNER, -1), Vector2(ROTOR_INNER, 0), Vector2(ROTOR_INNER, 1), Vector2(0.85, 1), Vector2(1.0, 1), Vector2(1.0, 0), Vector2(1.0, -1), Vector2(0.85, -1)]
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
		# the axis of this drilled hole, so its wall can be shaded as a bore rather than as loose facets
		var hole_centre := Vector3.ZERO
		for point in holes:
			hole_centre += point
		hole_centre /= float(holes.size())
		for i in 8:
			var j := (i + 1) % 8
			for side in [-1.0, 1.0]:
				# the face is flat steel: one normal for every vertex, pointing out of the disc on its own side. Letting
				# the faces and the hole walls share generated normals is what put dark wedges round every hole.
				var offset := Vector3(side * face, 0, 0)
				for point in [edges[i], edges[j], holes[i], holes[i], edges[j], holes[j]]:
					surface.set_normal(Vector3(side, 0.0, 0.0))
					surface.add_vertex(point + offset)
			# the wall of each drilled hole, so the hole is a bore through 5 mm of steel rather than a hole in a sheet;
			# its normal points in at the bore axis at every vertex, which is what a hole wall does
			for pair in [[holes[i], -1.0], [holes[j], -1.0], [holes[i], 1.0], [holes[i], 1.0], [holes[j], -1.0], [holes[j], 1.0]]:
				var p: Vector3 = pair[0]
				var bore_normal := Vector3(0.0, hole_centre.y - p.y, hole_centre.z - p.z).normalized()
				surface.set_normal(bore_normal)
				surface.add_vertex(p + Vector3(pair[1] * face, 0.0, 0.0))
	return surface.commit()


# A flat ABS sensor ring: a steel annulus with a row of rectangular windows punched round its middle. That is what an
# axial-style target wheel looks like from the side - stripes of steel and slots - and it is what the pickup's pole piece
# reads as the windows pass it. Drawing the teeth as a zig-zag on the outer edge (the earlier version) left the face
# solid and made the ring read as a star instead.
#
# Solid like the disc: two faces, a rim on the outside and one on the bore, and four walls inside every window, all with
# explicit normals so the ring reads as machined steel rather than as a paper washer.


static func tone_ring_mesh(inner: float, outer: float, thickness: float, teeth: int) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := thickness * 0.5
	var window_lo := lerpf(inner, outer, TONE_RING_WINDOW_LO)
	var window_hi := lerpf(inner, outer, TONE_RING_WINDOW_HI)
	var segments := 64
	var pitch := TAU / float(teeth)
	# the two rims that stay solid all the way round, on both faces
	for side in [-1.0, 1.0]:
		var x: float = side * half
		for i in segments:
			var a := TAU * float(i) / float(segments)
			var b := TAU * float(i + 1) / float(segments)
			face_patch(surface, x, inner, window_lo, a, b, side)
			face_patch(surface, x, window_hi, outer, a, b, side)
	# the windowed band: a solid strip either side of each window, and a hole straight through the middle of it
	var open_half := pitch * TONE_RING_DUTY * 0.5
	for i in teeth:
		var start := pitch * float(i)
		var mid := start + pitch * 0.5
		var open_from := mid - open_half
		var open_to := mid + open_half
		for side in [-1.0, 1.0]:
			var x: float = side * half
			face_patch(surface, x, window_lo, window_hi, start, open_from, side)
			face_patch(surface, x, window_lo, window_hi, open_to, start + pitch, side)
		# the four walls of the window, full thickness
		radial_wall(surface, window_lo, open_from, open_to, half, -1.0)
		radial_wall(surface, window_hi, open_from, open_to, half, 1.0)
		tangent_wall(surface, window_lo, window_hi, open_from, half, -1.0)
		tangent_wall(surface, window_lo, window_hi, open_to, half, 1.0)
	# the outer rim and the bore, so the ring is closed
	for i in segments:
		var a := TAU * float(i) / float(segments)
		var b := TAU * float(i + 1) / float(segments)
		rim_wall(surface, outer, half, a, b, 1.0)
		rim_wall(surface, inner, half, a, b, -1.0)
	return surface.commit()


# A flat patch of the ring's face at x, between two radii, over the angular span a..b, facing side * +x.


static func face_patch(surface: SurfaceTool, x: float, r_in: float, r_out: float, a: float, b: float, side: float) -> void:
	var normal := Vector3(side, 0.0, 0.0)
	var p := Vector3(x, r_in * cos(a), r_in * sin(a))
	var q := Vector3(x, r_out * cos(a), r_out * sin(a))
	var s := Vector3(x, r_in * cos(b), r_in * sin(b))
	var t := Vector3(x, r_out * cos(b), r_out * sin(b))
	for v in [p, q, s, s, q, t]:
		surface.set_normal(normal)
		surface.add_vertex(v)


# One wall of a window along a constant radius: it faces the bore (-1) or away from the axle (+1).


static func radial_wall(surface: SurfaceTool, radius: float, a: float, b: float, half: float, facing: float) -> void:
	var na := Vector3(0.0, cos(a), sin(a)) * facing
	var nb := Vector3(0.0, cos(b), sin(b)) * facing
	var items := [[Vector3(-half, radius * cos(a), radius * sin(a)), na], [Vector3(half, radius * cos(a), radius * sin(a)), na],
		[Vector3(-half, radius * cos(b), radius * sin(b)), nb], [Vector3(-half, radius * cos(b), radius * sin(b)), nb],
		[Vector3(half, radius * cos(a), radius * sin(a)), na], [Vector3(half, radius * cos(b), radius * sin(b)), nb]]
	for item in items:
		surface.set_normal(item[1])
		surface.add_vertex(item[0])


# One wall across a window at one of its angular ends, spanning the band radially: the side of the slot.


static func tangent_wall(surface: SurfaceTool, r_lo: float, r_hi: float, angle: float, half: float, facing: float) -> void:
	var normal := Vector3(0.0, -sin(angle), cos(angle)) * facing
	var p := Vector3(-half, r_lo * cos(angle), r_lo * sin(angle))
	var q := Vector3(-half, r_hi * cos(angle), r_hi * sin(angle))
	var s := Vector3(half, r_lo * cos(angle), r_lo * sin(angle))
	var t := Vector3(half, r_hi * cos(angle), r_hi * sin(angle))
	for item in [[p, normal], [q, normal], [s, normal], [s, normal], [q, normal], [t, normal]]:
		surface.set_normal(item[1])
		surface.add_vertex(item[0])


# A cylindrical wall of the ring at one radius: its outer edge (facing +1) or its bore (facing -1).


static func rim_wall(surface: SurfaceTool, radius: float, half: float, a: float, b: float, facing: float) -> void:
	var na := Vector3(0.0, cos(a), sin(a)) * facing
	var nb := Vector3(0.0, cos(b), sin(b)) * facing
	var items := [[Vector3(-half, radius * cos(a), radius * sin(a)), na], [Vector3(half, radius * cos(a), radius * sin(a)), na],
		[Vector3(-half, radius * cos(b), radius * sin(b)), nb], [Vector3(-half, radius * cos(b), radius * sin(b)), nb],
		[Vector3(half, radius * cos(a), radius * sin(a)), na], [Vector3(half, radius * cos(b), radius * sin(b)), nb]]
	for item in items:
		surface.set_normal(item[1])
		surface.add_vertex(item[0])


# A cylinder band of the given radius, thickness and facing: the edge of a disc. Explicit normals, because the faces
# beside it are generated by winding and a band needs to be lit from its own side.


static func band_mesh(radius: float, thickness: float, outward: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 96
	var half := thickness * 0.5
	for i in sides:
		var a := TAU * i / sides
		var b := TAU * (i + 1) / sides
		var na := Vector3(0.0, cos(a), sin(a)) * outward
		var nb := Vector3(0.0, cos(b), sin(b)) * outward
		var p := Vector3(-half, radius * cos(a), radius * sin(a))
		var q := Vector3(half, radius * cos(a), radius * sin(a))
		var s := Vector3(-half, radius * cos(b), radius * sin(b))
		var t := Vector3(half, radius * cos(b), radius * sin(b))
		for item in [[p, na], [q, na], [s, nb], [s, nb], [q, na], [t, nb]]:
			surface.set_normal(item[1])
			surface.add_vertex(item[0])
	return surface.commit()


# The disc's carrier: a solid hub, a solid rim and six narrow arms, with open windows between them. Real floating-disc
# carriers are spoked like this, and the windows are what lets the ABS tone ring's slots look through to the air behind
# instead of at a solid plate - a ring bolted flat onto a solid carrier reads as painted-on holes whatever shape the
# slots are.


static func carrier_mesh(inner: float, outer: float, thickness: float, arms: int) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := thickness * 0.5
	var band := outer - inner
	var hub_r := inner + band * 0.30 # solid centre, where the disc bolts to the wheel
	var rim_r := outer - band * 0.18 # solid rim, where the friction ring is riveted on
	var segments := 96
	var pitch := TAU / float(arms)
	var arm_half := pitch * 0.16 # the arms are narrow, so most of the band is open
	# the hub and the rim stay solid all the way round
	for side in [-1.0, 1.0]:
		var x: float = side * half
		for i in segments:
			var a := TAU * float(i) / float(segments)
			var b := TAU * float(i + 1) / float(segments)
			face_patch(surface, x, inner, hub_r, a, b, side)
			face_patch(surface, x, rim_r, outer, a, b, side)
	# six arms across the open band, centred on the disc bolts
	for i in arms:
		var centre := pitch * float(i)
		for side in [-1.0, 1.0]:
			var x: float = side * half
			face_patch(surface, x, hub_r, rim_r, centre - arm_half, centre + arm_half, side)
		# the sides of the arm, then the steps down to the hub and up to the rim
		tangent_wall(surface, hub_r, rim_r, centre - arm_half, half, -1.0)
		tangent_wall(surface, hub_r, rim_r, centre + arm_half, half, 1.0)
		radial_wall(surface, hub_r, centre - pitch * 0.5 + arm_half, centre - arm_half, half, 1.0)
		radial_wall(surface, rim_r, centre - pitch * 0.5 + arm_half, centre - arm_half, half, -1.0)
	return surface.commit()
