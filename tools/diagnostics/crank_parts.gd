extends SceneTree

# Prints the axial extents and outer radii of every crankshaft part, so gaps between parts show up as numbers
# instead of guesses. Run: godot --headless --path . -s res://tools/diagnostics/crank_parts.gd

func _init() -> void:
	var spec := EngineSpec.new()
	var preset: Dictionary = Presets.PRESETS["honda_cbr250rr"]
	for key in preset.keys():
		spec.set(key, preset[key])
	var model := EngineModel.new()
	get_root().add_child(model)
	model.build(spec)
	var crank := model._crank_node as Crankshaft
	var m := Units.M_TO_SCENE
	var rows: Array = []
	_collect(crank, crank, rows)
	rows.sort_custom(func(a, b): return a["from"] < b["from"])
	for r in rows:
		print("%-16s x %8.2f .. %8.2f mm   radius %6.2f mm" % [r["name"], r["from"] / m * 1000.0, r["to"] / m * 1000.0, r["radius"] / m * 1000.0])
	# axial gaps between consecutive parts
	for i in rows.size() - 1:
		var gap: float = rows[i + 1]["from"] - rows[i]["to"]
		if gap > 0.0005:
			print("GAP %.2f mm after %s" % [gap / m * 1000.0, rows[i]["name"]])
	quit(0)


func _collect(node: Node, crank: Crankshaft, rows: Array) -> void:
	for child in node.get_children():
		if child is CSGPolygon3D:
			var csg := child as CSGPolygon3D
			var xf := _to_crank(csg, crank)
			rows.append({
				"name": csg.name, "from": xf.origin.x - csg.depth * 0.5, "to": xf.origin.x + csg.depth * 0.5,
				"radius": _outline_radius(csg.polygon),
			})
		elif child is MeshInstance3D:
			var mi := child as MeshInstance3D
			if mi.mesh is CylinderMesh:
				var mesh := mi.mesh as CylinderMesh
				var xf := _to_crank(mi, crank)
				# a cylinder with rotation.z = 90 degrees runs along x; take its world space extents
				var aabb := xf * mesh.get_aabb()
				rows.append({
					"name": mi.name, "from": aabb.position.x, "to": aabb.position.x + aabb.size.x,
					"radius": maxf(aabb.size.y, aabb.size.z) * 0.5,
				})
		_collect(child, crank, rows)


func _to_crank(node: Node3D, crank: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node3D = node
	while n != null and n != crank:
		xf = n.transform * xf
		n = n.get_parent() as Node3D
	return xf


func _outline_radius(poly: PackedVector2Array) -> float:
	var r := 0.0
	for p in poly:
		r = maxf(r, p.length())
	return r
