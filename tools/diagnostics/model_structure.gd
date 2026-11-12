extends SceneTree

# Prints the 3D structure of the bike, node by node, with the mesh each part carries and what it costs. The model is built
# in code, so a tree is the only way to see the result instead of reading forty build() functions.
#
# It builds the parts directly rather than borrowing the running scene: a live Drivetrain is rebuilt on every panel change
# and Godot hands out generated node names for the ones that come and go, which makes the dump unreadable.
# Run: godot --headless --path . -s res://tools/diagnostics/model_structure.gd

const OUT_PATH := "res://tools/diagnostics/out/model_structure.txt"
const PRESET := "honda_cbr1000rrr_sp"
const MAX_DEPTH := 9


func _init() -> void:
	var spec := EngineSpec.new()
	var preset: Dictionary = Presets.PRESETS[PRESET]
	for key in preset.keys():
		spec.set(key, preset[key])

	var model := EngineModel.new()
	get_root().add_child(model)
	model.build(spec)
	var dt := Drivetrain.new()
	get_root().add_child(dt)
	dt.build(Ground.Y, GearboxModel.countershaft_position(model.crank_position(), spec), Vector3(0.0, 4.0, 0.0),
		1.5, spec.abs_hardware(), AABB(), spec, PRESET)
	var clutch := Clutch.new()
	get_root().add_child(clutch)
	clutch.build(model.crank_position(), spec, model.primary_gear_x())
	var gearbox := GearboxModel.new()
	get_root().add_child(gearbox)
	gearbox.build(model.crank_position(), spec, model.primary_gear_x())
	await process_frame

	var lines: PackedStringArray = []
	var totals := {"nodes": 0, "meshes": 0, "tris": 0}
	for part in [model, dt, clutch, gearbox]:
		lines.append("%s  <%s>" % [part.name if not part.name.begins_with("@") else part.get_script().resource_path.get_file().get_basename(), part.get_class()])
		for child in part.get_children():
			_walk(child, 1, lines, totals)
	var text := "\n".join(lines)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/diagnostics/out"))
	var file := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	file.store_string(text + "\n")
	file.close()
	print("total: %d nodes, %d meshes, %d triangles" % [totals.nodes, totals.meshes, totals.tris])
	print("written to %s (%d lines)" % [OUT_PATH, lines.size()])
	quit(0)


# A node's name, or for the ones added without one, the script that makes them.
func _label(node: Node) -> String:
	if not node.name.begins_with("@"):
		return str(node.name)
	var script := node.get_script() as Script if node.get_script() != null else null
	if script != null:
		var global_name := str(script.get_global_name())
		if not global_name.is_empty():
			return global_name
		return script.resource_path.get_file().get_basename()
	return str(node.name)


# One line per node: depth, name, class, and what the mesh costs.
func _walk(node: Node, depth: int, lines: PackedStringArray, totals: Dictionary) -> void:
	totals.nodes += 1
	var suffix := ""
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var tris := _triangles(mi.mesh)
		if mi.mesh != null:
			totals.meshes += 1
			totals.tris += tris
			suffix = "  [%s, %d tris]" % [mi.mesh.get_class(), tris]
		if not mi.visible:
			suffix += " (hidden)"
	elif node is CSGPolygon3D:
		suffix = "  [CSG, evaluated at runtime]"
	elif node is Label3D:
		suffix = "  [Label3D \"%s\"]" % (node as Label3D).text
	if depth > MAX_DEPTH:
		return
	lines.append("%s%s  <%s>%s" % ["  ".repeat(depth), _label(node), node.get_class(), suffix])
	for child in node.get_children():
		_walk(child, depth + 1, lines, totals)


func _triangles(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	if mesh is ArrayMesh:
		var arrays := (mesh as ArrayMesh).surface_get_arrays(0)
		return (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	if mesh is PrimitiveMesh:
		var arrays := (mesh as PrimitiveMesh).get_mesh_arrays()
		return (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return 0
