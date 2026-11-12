extends SceneTree

# A brake disc is one piece of steel, not two flat sheets standing next to each other. The faces carry the drilled
# holes; the rim and the inner edge close them into 5 mm of material, and the carrier plate is closed the same way.
# This measures the drawn geometry and holds it to that shape.
# Run: godot --headless --path . -s tests/unit/geometry/brake_rotor_test.gd (exit code 1 on failure)

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


# What the vertex normals say: a flat face points straight out of the disc (+x or -x), a hole wall points at its bore
# and nothing in between, and nothing is left un-normalised (a zero normal renders black, which is what the shaded
# wedges round the holes used to look like).
func normals_of(mi: MeshInstance3D) -> Dictionary:
	var arrays := (mi.mesh as ArrayMesh).surface_get_arrays(0)
	if arrays[Mesh.ARRAY_NORMAL] == null:
		return {"zero": 1, "face": 0, "wall": 0, "mixed": 0}
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var zero := 0
	var face := 0
	var wall := 0
	var mixed := 0
	for n in normals:
		if n.length() < 0.9:
			zero += 1
		elif absf(n.x) > 0.999:
			face += 1
		elif absf(n.x) < 0.001:
			wall += 1
		else:
			mixed += 1
	return {"zero": zero, "face": face, "wall": wall, "mixed": mixed}


func spec_of(id: String) -> EngineSpec:
	var spec := EngineSpec.new()
	var preset: Dictionary = Presets.PRESETS[id]
	for key in preset.keys():
		spec.set(key, preset[key])
	return spec


# Vertices in the drawn brake assembly, so a geometry change can be measured rather than assumed.
func _assembly_vertices(dt: Drivetrain) -> int:
	var total := 0
	for wheel in [dt._front_wheel, dt._wheel_pivot]:
		for part in ["BrakeRotor", "RotorCarrier"]:
			var node: Node = wheel.get_node_or_null(part)
			if node != null:
				total += _count_verts(node)
	return total


# World-space bounds of any mesh instance under a node (the node itself if it is one).
func _world_bounds(node: Node) -> AABB:
	if node is MeshInstance3D:
		return (node as MeshInstance3D).global_transform * (node as MeshInstance3D).mesh.get_aabb()
	var total := AABB()
	var first := true
	for child in node.get_children():
		var box := _world_bounds(child)
		if box.size == Vector3.ZERO:
			continue
		total = box if first else total.merge(box)
		first = false
	return total


func _count_verts(node: Node) -> int:
	var count := 0
	if node is MeshInstance3D and (node as MeshInstance3D).mesh is ArrayMesh:
		var arrays := ((node as MeshInstance3D).mesh as ArrayMesh).surface_get_arrays(0)
		count += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	for child in node.get_children():
		count += _count_verts(child)
	return count


# Radii and axial extent of a mesh's vertices about the wheel's x axis.
func measure(mi: MeshInstance3D) -> Dictionary:
	var arrays := (mi.mesh as ArrayMesh).surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var r_min := INF
	var r_max := 0.0
	var x_min := INF
	var x_max := -INF
	for v in verts:
		var r := Vector2(v.y, v.z).length()
		r_min = minf(r_min, r)
		r_max = maxf(r_max, r)
		x_min = minf(x_min, v.x)
		x_max = maxf(x_max, v.x)
	return {"r_min": r_min, "r_max": r_max, "x_min": x_min, "x_max": x_max, "verts": verts.size()}


# The distinct radii a mesh's vertices sit at, sorted: a flat ring lands on a handful of them and they are its structure.
func _radii_of(verts: PackedVector3Array) -> Array[float]:
	var radii: Array[float] = []
	for v in verts:
		var r := Vector2(v.y, v.z).length()
		var known := false
		for k in radii:
			if absf(k - r) < 1e-4:
				known = true
		if not known:
			radii.append(r)
	radii.sort()
	return radii


# The side walls of the windows, as a count. A window punched through the ring has two walls facing round the ring
# (one at each of its ends), so a real ring gives 2 * teeth of them. A star-shaped silhouette has none, and a solid face
# has none: this is what tells a perforated ring from a saw-edged one.
func _window_walls(tone: MeshInstance3D) -> int:
	var arrays := (tone.mesh as ArrayMesh).surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var half := Drivetrain.TONE_RING_THICKNESS * 0.5
	var angles: Array[float] = []
	for i in verts.size():
		var n := normals[i]
		# a side wall faces round the ring: its normal is tangential, with no radial or axial component
		if absf(n.x) > 0.02 or Vector2(n.y, n.z).length() < 0.98:
			continue
		var radial := Vector3(0.0, verts[i].y, verts[i].z).normalized()
		if absf(n.dot(radial)) > 0.02:
			continue
		var angle := fposmod(atan2(verts[i].z, verts[i].y), TAU)
		var known := false
		for k in angles:
			if absf(k - angle) < 1e-4:
				known = true
		if not known:
			angles.append(angle)
	return angles.size()


func _init() -> void:
	await process_frame
	var drivetrain := Drivetrain.new()
	root.add_child(drivetrain)
	drivetrain.build(Ground.Y, Vector3.ZERO, Vector3(0.0, 4.0, 0.0), 1.5)
	var checked := 0
	for wheel in [drivetrain._front_wheel, drivetrain._wheel_pivot]:
		var rotor := wheel.get_node_or_null("BrakeRotor") as MeshInstance3D
		check(rotor != null, "the wheel carries a brake rotor")
		if rotor == null:
			continue
		var faces := measure(rotor)
		var thickness: float = faces.x_max - faces.x_min
		var outer_r: float = faces.r_max
		print("%s rotor: Ø %.0f mm, %.1f mm thick, ring %.0f-%.0f mm from the axle, %d vertices on the faces" % [
			"front" if wheel == drivetrain._front_wheel else "rear",
			outer_r * 200.0, thickness * 100.0, faces.r_min * 100.0, faces.r_max * 100.0, faces.verts])
		check(absf(thickness - Drivetrain.ROTOR_THICKNESS) < 0.002,
			"the disc is %.1f mm of steel" % (thickness * 100.0))
		# shading: flat faces, bore walls, nothing in between and nothing un-normalised
		var normals := normals_of(rotor)
		print("  normals: %d on the faces, %d on the hole walls, %d zero-length, %d ambiguous" % [
			normals.face, normals.wall, normals.zero, normals.mixed])
		check(normals.zero == 0, "every vertex carries a normal (%d were left un-normalised)" % normals.zero)
		check(normals.mixed == 0, "no normal mixes a face and a hole wall (%d did)" % normals.mixed)
		check(normals.wall > 0, "the drilled holes have walls with their own normals")
		check(normals.face > normals.wall, "most of the mesh is the two faces")
		# the edges that make it solid
		var outer_edge := rotor.get_node_or_null("RotorEdgeOuter") as MeshInstance3D
		var inner_edge := rotor.get_node_or_null("RotorEdgeInner") as MeshInstance3D
		check(outer_edge != null and inner_edge != null, "the disc has a rim and an inner edge, not just two faces")
		if outer_edge != null and inner_edge != null:
			var band := measure(outer_edge)
			var band_inner := measure(inner_edge)
			print("  edges: rim %.0f mm (band %.1f mm thick), inner %.0f mm, band spans x %.3f..%.3f" % [
				band.r_max * 100.0, (band.x_max - band.x_min) * 100.0, band_inner.r_max * 100.0, band.x_min, band.x_max])
			check(absf(band.r_max - outer_r) < 0.002, "the rim sits on the disc's outer radius (%.3f vs %.3f)" % [band.r_max, outer_r])
			check(absf((band.x_max - band.x_min) - Drivetrain.ROTOR_THICKNESS) < 0.002,
				"the rim is as thick as the disc (%.1f mm)" % ((band.x_max - band.x_min) * 100.0))
			check(absf(band_inner.r_max - outer_r * Drivetrain.ROTOR_INNER) < 0.003,
				"the inner edge sits where the friction ring starts (%.3f vs %.3f)" % [band_inner.r_max, outer_r * Drivetrain.ROTOR_INNER])
			# a band is a wall: its vertices all sit at one radius, so it fills the gap between the two faces
			check(band.r_max - band.r_min < 0.002, "the rim is a wall, not another flat ring (radial spread %.4f)" % (band.r_max - band.r_min))
		# the carrier plate is closed too
		var carrier := rotor.get_parent().get_node_or_null("RotorCarrier") as MeshInstance3D
		check(carrier != null and carrier.get_node_or_null("CarrierEdgeOuter") != null and carrier.get_node_or_null("CarrierEdgeInner") != null,
			"the carrier plate has its edges closed")
		check(carrier != null and carrier.get_node_or_null("ABSToneRing") == null,
			"a bike without ABS has no sensor ring")
		checked += 1
	check(checked == 2, "both wheels were checked")

	# ---- ABS changes the disc: the sensor ring appears on the carrier, and it is a toothed steel ring ----
	var plain_verts := _assembly_vertices(drivetrain)
	for case in [["selected", true], ["preset honda_cbr1000rrr_sp", spec_of("honda_cbr1000rrr_sp").has_abs],
			["preset kawasaki_h2r", spec_of("kawasaki_h2r").has_abs]]:
		var abs_bike := Drivetrain.new()
		root.add_child(abs_bike)
		abs_bike.build(Ground.Y, Vector3.ZERO, Vector3(0.0, 4.0, 0.0), 1.5, bool(case[1]))
		var ring_count := 0
		for wheel in [abs_bike._front_wheel, abs_bike._wheel_pivot]:
			var carrier := wheel.get_node_or_null("RotorCarrier") as Node3D
			var tone: MeshInstance3D = null
			if carrier != null:
				tone = carrier.get_node_or_null("ABSToneRing") as MeshInstance3D
			if case[1]:
				check(tone != null, "%s: the disc carries an ABS sensor ring" % case[0])
				if tone != null:
					ring_count += 1
					var ring := measure(tone)
					var radii := _radii_of((tone.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array)
					print("%s: sensor ring %.0f-%.0f mm, %.1f mm thick, %d distinct radii, windows %d%% of the band" % [
						case[0], ring.r_min * 100.0, ring.r_max * 100.0, (ring.x_max - ring.x_min) * 100.0,
						radii.size(), roundi((radii[2] - radii[1]) / (radii[3] - radii[0]) * 100.0) if radii.size() >= 4 else 0])
					check(absf((ring.x_max - ring.x_min) - Drivetrain.TONE_RING_THICKNESS) < 0.002,
						"%s: the ring is %.1f mm thick" % [case[0], (ring.x_max - ring.x_min) * 100.0])
					# a real ring of this style is a flat annulus with a row of rectangular windows punched round it: four
					# radii (bore, both edges of the window band, rim) and a face cut into strips
					check(radii.size() >= 4, "%s: the ring has a bore, a window band and a rim (%d radii)" % [case[0], radii.size()])
					if radii.size() >= 4:
						var window_share: float = (radii[2] - radii[1]) / (radii[3] - radii[0])
						check(window_share > 0.4, "%s: the windows span %.0f%% of the band" % [case[0], window_share * 100.0])
					var walls := _window_walls(tone)
					print("  windows: %d side walls, i.e. %d punched slots (%d teeth %.1f mm wide)" % [
						walls, walls / 2, Drivetrain.TONE_RING_TEETH,
						TAU * radii[1] / float(Drivetrain.TONE_RING_TEETH) * 100.0 * (1.0 - Drivetrain.TONE_RING_DUTY)])
					check(walls == Drivetrain.TONE_RING_TEETH * 2,
						"%s: %d window walls for %d windows, so the face is pierced in stripes (a star edge or a solid disc would have none)" % [
							case[0], walls, Drivetrain.TONE_RING_TEETH])
			else:
				check(tone == null, "%s: no ABS, so no sensor ring" % case[0])
		if case[1]:
			check(ring_count == 2, "%s: both wheels carry the ring (got %d)" % [case[0], ring_count])
		var abs_verts := _assembly_vertices(abs_bike)
		if case[1]:
			check(abs_verts > plain_verts, "the disc assembly changes with ABS (%d vs %d vertices)" % [abs_verts, plain_verts])
		root.remove_child(abs_bike)
		abs_bike.free()
	# ---- the pickup has to be able to read the ring: same side of the disc, a millimetre away, at tooth height ----
	var abs_probe := Drivetrain.new()
	root.add_child(abs_probe)
	abs_probe.build(Ground.Y, Vector3.ZERO, Vector3(0.0, 4.0, 0.0), 1.5, true)
	var hardware := abs_probe.get_node("BrakeHardware")
	for pair in [["front", abs_probe._front_wheel, "FrontABSSensor"], ["rear", abs_probe._wheel_pivot, "RearABSSensor"]]:
		var wheel: Node3D = pair[1]
		var disc := wheel.get_node("BrakeRotor") as MeshInstance3D
		var ring := (wheel.get_node("RotorCarrier") as Node3D).get_node("ABSToneRing") as MeshInstance3D
		var ring_box := _world_bounds(ring)
		var disc_x := disc.global_position.x
		var sensor := hardware.get_node(pair[2]) as MeshInstance3D
		# the pick-up is a bar, so measure its axis ends rather than its bounding box (the box is inflated by the radius)
		var bar := sensor.mesh as CylinderMesh
		var end_a: Vector3 = sensor.global_transform * Vector3(0.0, bar.height * 0.5, 0.0)
		var end_b: Vector3 = sensor.global_transform * Vector3(0.0, -bar.height * 0.5, 0.0)
		var tip_point := end_a if absf(end_a.x) < absf(end_b.x) else end_b # the end nearest the axle
		var tip := tip_point.x
		# the outboard face of the ring is the one further from the wheel centre
		var ring_face := ring_box.position.x if disc_x < 0.0 else ring_box.end.x
		var gap := absf(tip - ring_face)
		var pickup_r := Vector2(tip_point.y - wheel.global_position.y, tip_point.z - wheel.global_position.z).length()
		var ring_r := measure(ring)
		var same_side := (ring_box.position.x - disc_x) * signf(disc_x) >= -0.001 and (tip - disc_x) * signf(disc_x) >= -0.001
		print("%s: ring face x %.3f, pickup tip x %.3f, %.1f mm of air, pickup at %.1f mm radius (ring %.1f-%.1f mm)" % [
			pair[0], ring_face, tip, gap * 100.0, pickup_r * 100.0, ring_r.r_min * 100.0, ring_r.r_max * 100.0])
		check(same_side, "%s: the pickup and the ring are on the same side of the disc" % pair[0])
		# a real wheel-speed pickup runs 0.3-5 mm off its target ring
		check(gap > 0.003 and gap < 0.05, "%s: the pickup sits %.1f mm from the ring face" % [pair[0], gap * 100.0])
		# the pole piece has to sit over the windowed band, not over one of the solid rims either side of it: on a ring
		# of four radii (bore, window inner, window outer, rim) that means between the two window radii
		var radii := _radii_of((ring.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array)
		var band_lo: float = radii[1] if radii.size() >= 4 else ring_r.r_min
		var band_hi: float = radii[2] if radii.size() >= 4 else ring_r.r_max
		check(pickup_r > band_lo and pickup_r < band_hi,
			"%s: the pickup reads over the windows (%.1f mm, band %.1f-%.1f mm)" % [pair[0], pickup_r * 100.0, band_lo * 100.0, band_hi * 100.0])
		check(Drivetrain.TONE_RING_TEETH >= 40 and Drivetrain.TONE_RING_TEETH <= 52,
			"%s: %d teeth, inside the 44-52 a real reluctor ring uses" % [pair[0], Drivetrain.TONE_RING_TEETH])
	root.remove_child(abs_probe)
	abs_probe.free()

	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
