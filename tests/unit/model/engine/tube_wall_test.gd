extends SceneTree

# An open tube end is a hole, and a hole with no wall looks like paper. The throttle body bore and the exhaust outlet are
# both open, so both are built with a real wall: this measures the drawn geometry and holds the wall to the thickness the
# model claims (3.5 mm of cast aluminium at the throttle bore, 1.2 mm of steel at the pipe mouth).
# Run: godot --headless --path . -s tests/unit/geometry/tube_wall_test.gd (exit code 1 on failure)

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


func _init() -> void:
	await process_frame

	# ---- throttle body: the bore is open at both ends, and its wall is the specced 3.5 mm ----
	var spec := EngineSpec.new()
	var preset: Dictionary = Presets.PRESETS["honda_cbr250rr"]
	for key in preset.keys():
		spec.set(key, preset[key])
	var model := EngineModel.new()
	root.add_child(model)
	model.build(spec)
	check(model._throttle_bodies.size() > 0, "the model draws a throttle body")
	var body: Node3D = model._throttle_bodies[0]
	var tube := body.get_child(0) as MeshInstance3D
	check(tube != null and tube.mesh is ArrayMesh, "the throttle bore is built as its own mesh (so it can be hollow)")
	if tube != null and tube.mesh is ArrayMesh:
		var arrays := (tube.mesh as ArrayMesh).surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var r_min := INF
		var r_max := 0.0
		for v in verts:
			var r := Vector2(v.x, v.z).length() # the tube runs along the node's Y axis
			r_min = minf(r_min, r)
			r_max = maxf(r_max, r)
		var wall := r_max - r_min
		var bore_mm: float = body.get_meta("bore") * 100.0
		print("throttle body: outer bore Ø %.1f mm, inner Ø %.1f mm, wall %.2f mm over %d vertices" % [
			r_max * 200.0, r_min * 200.0, wall * 100.0, verts.size()])
		check(absf(wall - IntakeModel.OPEN_TUBE_WALL) < 0.002,
			"the throttle bore wall is %.2f mm, not %.1f mm" % [wall * 100.0, IntakeModel.OPEN_TUBE_WALL * 100.0])
		check(r_min > r_max * 0.5, "the bore stays open: inner radius %.3f vs outer %.3f" % [r_min, r_max])
		check(r_max > bore_mm * 0.005, "the bore is at least the specced Ø%.0f mm" % bore_mm)
	root.remove_child(model)
	model.free()

	# ---- exhaust: an uncapped pipe mouth is lined and rimmed, a capped one is not ----
	var pts := PackedVector3Array([Vector3.ZERO, Vector3(0.0, 0.0, -1.0)])
	var radii := PackedFloat32Array([0.2, 0.2])
	var open_mesh := Exhaust._tube(pts, radii, false, Exhaust.WALL)
	var open_verts: PackedVector3Array = open_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var mouth_min := INF
	var mouth_max := 0.0
	for v in open_verts:
		if absf(v.z + 1.0) < 1e-4: # vertices on the mouth plane
			var r := Vector2(v.x, v.y).length()
			mouth_min = minf(mouth_min, r)
			mouth_max = maxf(mouth_max, r)
	print("exhaust mouth: outer Ø %.1f mm, inner Ø %.1f mm, wall %.2f mm" % [mouth_max * 200.0, mouth_min * 200.0, (mouth_max - mouth_min) * 100.0])
	check(absf((mouth_max - mouth_min) - Exhaust.WALL) < 0.002,
		"the pipe mouth shows a %.2f mm wall, not %.1f mm" % [(mouth_max - mouth_min) * 100.0, Exhaust.WALL * 100.0])
	check(mouth_min > 0.1, "the pipe bore stays open (inner radius %.3f)" % mouth_min)
	var capped_mesh := Exhaust._tube(pts, radii, true, Exhaust.WALL)
	var capped_verts: PackedVector3Array = capped_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var capped_min := INF
	for v in capped_verts:
		if absf(v.z + 1.0) < 1e-4:
			capped_min = minf(capped_min, Vector2(v.x, v.y).length())
	# a capped end closes to the centre (radius 0), so there is no bore ring there and no wall to draw
	check(capped_min < 0.05, "a capped pipe end is still solid, closing at the centre (min radius %.3f)" % capped_min)

	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
