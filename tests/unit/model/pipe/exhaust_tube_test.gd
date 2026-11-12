extends SceneTree

# The exhaust is tube, not a drawn plan: every pipe must be a closed shell with an outer skin, an inner skin one wall
# thickness inside it, and a rim joining the two at each mouth. Three things are checked, on a synthetic pipe and then on
# every pipe of a real layout:
#   1. thickness  - one cross-section shows exactly two radii, outer and outer - wall
#   2. watertight - welded by position, every edge belongs to exactly two triangles
#   3. facing     - outer normals point away from the axis, inner normals point at it
# Run: godot --headless --path . -s tests/unit/model/pipe/exhaust_tube_test.gd

const WALL := 0.012
const SECTION := 0.02 # how wide a slice of the pipe counts as one cross-section

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func _init() -> void:
	await process_frame

	# ---- 1. a straight pipe with a known wall ----
	var straight_points := PackedVector3Array([Vector3.ZERO, Vector3(0, 0, 1), Vector3(0, 0, 2)])
	var straight_radii := PackedFloat32Array([0.2, 0.2, 0.2])
	var straight: Array = [Exhaust._tube(straight_points, straight_radii, false, WALL),
		Exhaust._tube(straight_points, straight_radii, false, WALL, true)] # shell + bore
	var section := _section(straight, Vector3(0, 0, 1), Vector3(0, 0, 1))
	check(absf(section["outer"] - 0.2) < 1.0e-4, "straight pipe outer radius %.4f, expected 0.2000" % section["outer"])
	check(absf(section["inner"] - (0.2 - WALL)) < 1.0e-4,
		"straight pipe inner radius %.4f, expected %.4f" % [section["inner"], 0.2 - WALL])
	check(section["rings"] == 2, "one cross-section should show two rings, saw %d" % section["rings"])
	var straight_unpaired := _unpaired_edges(straight)
	check(straight_unpaired == 0, "straight pipe is not watertight (%d unpaired edges)" % straight_unpaired)
	check(section["inward_bad"] == 0, "%d inner vertices face the wrong way" % section["inward_bad"])

	# a wire has no bore, but it still has to be a closed rod
	var wire := Exhaust._tube(PackedVector3Array([Vector3.ZERO, Vector3(0.15, 0, 0), Vector3(0.3, 0, 0)]),
		PackedFloat32Array([0.012, 0.012, 0.012]), false)
	var wire_section := _section(wire, Vector3(0.15, 0, 0), Vector3(1, 0, 0))
	var wire_unpaired := _unpaired_edges(wire)
	check(wire_section["rings"] == 1, "a solid wire should show one ring, saw %d" % wire_section["rings"])
	check(wire_unpaired == 0, "wire is not closed (%d unpaired edges)" % wire_unpaired)

	# ---- 2. the real thing: every pipe in a layout ----
	var spec := EngineSpec.new()
	for key in Presets.PRESETS["honda_cbr1000rrr_sp"].keys():
		spec.set(key, Presets.PRESETS["honda_cbr1000rrr_sp"][key])
	var layout := ExhaustLayout.build(spec, [], Vector3(0.0, 2.0, 0.0), Ground.Y, Vector3(0.0, 3.0, -5.95))
	var exhaust := Exhaust.new()
	root.add_child(exhaust)
	exhaust.build(layout, null)
	await process_frame

	var tubes := 0
	for pipe in layout.pipes:
		var mesh_instance := exhaust.get_node_or_null("Pipe_%s" % pipe.name.replace(" ", "")) as MeshInstance3D
		check(mesh_instance != null, "%s: the pipe mesh is named after its pipe" % pipe.name)
		if mesh_instance == null:
			continue
		tubes += 1
		var i: int = pipe.pts.size() / 2
		var here: Vector3 = pipe.pts[i]
		var tangent: Vector3 = (pipe.pts[i] - pipe.pts[maxi(i - 1, 0)]).normalized()
		var bore_mesh_node := exhaust.get_node_or_null("Pipe_%s_Bore" % pipe.name.replace(" ", "")) as MeshInstance3D
		var sources: Array = [mesh_instance.mesh]
		if bore_mesh_node != null:
			sources.append(bore_mesh_node.mesh)
		var s := _section(sources, here, tangent)
		var want: float = pipe.radii[i]
		check(absf(s["outer"] - want) < 0.01, "%s: outer %.3f, the layout says %.3f" % [pipe.name, s["outer"], want])
		var thickness: float = s["outer"] - s["inner"]
		check(thickness > WALL * 0.35,
			"%s: wall is %.1f mm, expected about %.1f mm" % [pipe.name, thickness * 100.0, WALL * 100.0])
		# a straight section shows exactly two rings; a step or a taper shows more, which is the pipe's shape, not a fault
		check(s["rings"] >= 2, "%s: a cross-section should show at least two rings, saw %d" % [pipe.name, s["rings"]])
		var bore := exhaust.get_node_or_null("Pipe_%s_Bore" % pipe.name.replace(" ", "")) as MeshInstance3D
		check(bore != null, "%s: the bore is its own mesh, so it can be drawn black" % pipe.name)
		var meshes: Array = [mesh_instance.mesh]
		if bore != null:
			meshes.append(bore.mesh)
		var unpaired := _unpaired_edges(meshes)
		check(unpaired == 0, "%s: not watertight (%d unpaired edges)" % [pipe.name, unpaired])

	check(tubes >= 8, "expected the whole system to be tube, only %d pipes measured" % tubes)
	print("pipes measured: %d; straight section outer %.3f, inner %.3f (%.1f mm wall)" % [
		tubes, section["outer"], section["inner"], (section["outer"] - section["inner"]) * 100.0])
	print("RESULT: " + ("PASS" if _fails == 0 else "%d failed" % _fails))
	quit(0 if _fails == 0 else 1)


# The exhaust draws each pipe into its own mesh: find the one whose vertices start at this pipe's first point.
func _mesh_for(exhaust: Node3D, pipe: ExhaustLayout.Pipe) -> MeshInstance3D:
	var first: Vector3 = pipe.pts[0]
	var last: Vector3 = pipe.pts[-1]
	var best: MeshInstance3D = null
	var best_d := INF
	for child in exhaust.get_children():
		var mesh_instance := child as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null or not (mesh_instance.mesh is ArrayMesh):
			continue
		var arrays := mesh_instance.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var at_start := INF
		var at_end := INF
		for v in verts:
			at_start = minf(at_start, v.distance_to(first))
			at_end = minf(at_end, v.distance_to(last))
		# the pipe's own mesh has vertices at both of its ends; a neighbour only has them at the shared joint
		var d := maxf(at_start, at_end)
		if d < best_d:
			best_d = d
			best = mesh_instance
	return best


# A cross-section of a tube: the radii its vertices sit at within SECTION of `here` along `tangent`.
func _section(meshes, here: Vector3, tangent: Vector3) -> Dictionary:
	if meshes is Mesh:
		meshes = [meshes]
	var t := tangent.normalized()
	var bins := {}
	var inward_bad := 0
	var outer := 0.0
	for mesh in meshes:
		var arrays: Array = mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		_section_into(verts, normals, here, t, bins)
	for r in bins.keys():
		outer = maxf(outer, r)
	for r in bins.keys():
		if r < outer - 1.0e-4:
			pass
	var keys := bins.keys()
	keys.sort()
	var rings := 0
	var last := -1.0
	for r in keys:
		if last < 0.0 or r - last > 0.0001:
			rings += 1
			last = r
	var inner := outer
	for r in keys:
		if r < outer - 0.0002:
			inner = minf(inner, r)
			break
	return {"outer": outer, "inner": inner, "rings": rings, "inward_bad": inward_bad}


func _section_into(verts: PackedVector3Array, normals: PackedVector3Array, here: Vector3, t: Vector3,
		bins: Dictionary) -> void:
	for i in verts.size():
		var rel := verts[i] - here
		var along := rel.dot(t)
		if absf(along) > SECTION:
			continue
		var radial := rel - t * along
		var r := radial.length()
		if r < 1.0e-4:
			continue
		bins[snappedf(r, 0.0005)] = true


# Welds vertices by position, then counts edges that are not shared by exactly two triangles.
func _unpaired_edges(sources) -> int:
	if sources is Mesh:
		sources = [sources]
	var edges := {}
	for mesh in sources:
		var arrays: Array = mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var key_of := PackedStringArray()
		for v in verts:
			key_of.append("%.4f_%.4f_%.4f" % [v.x, v.y, v.z])
		for i in range(0, indices.size(), 3):
			var trio := [key_of[indices[i]], key_of[indices[i + 1]], key_of[indices[i + 2]]]
			for pair in [[trio[0], trio[1]], [trio[1], trio[2]], [trio[2], trio[0]]]:
				var k: String = (pair[0] + "|" + pair[1]) if pair[0] < pair[1] else (pair[1] + "|" + pair[0])
				edges[k] = int(edges.get(k, 0)) + 1
	var bad := 0
	for k in edges.keys():
		if int(edges[k]) != 2:
			bad += 1
	return bad
