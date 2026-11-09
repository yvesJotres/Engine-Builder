class_name Exhaust
extends Node3D

# Draws an ExhaustLayout: header pipes, collector, catalytic converter, mid pipe, muffler and tailpipe.

const SEGMENTS := 20 # sides around each tube


func build(layout: ExhaustLayout) -> void:
	for c in get_children():
		c.queue_free()
	var header := _metal(Color(0.74, 0.74, 0.78), 0.4, 0.3)
	var cat := _metal(Color(0.5, 0.38, 0.28), 0.6, 0.2)
	var muffler := _metal(Color(0.36, 0.37, 0.42), 0.4, 0.3)
	var chrome := _metal(Color(0.92, 0.92, 0.95), 0.25, 0.4)
	var clamp_mat := _metal(Color(0.45, 0.45, 0.5), 0.45, 0.3)
	for pipe in layout.pipes:
		var mat: Material = header
		match pipe.kind:
			"catalyst":
				mat = cat
			"muffler":
				mat = muffler
			"tail":
				mat = chrome
		_add_mesh(_tube(pipe.pts, pipe.radii, pipe.kind == "muffler"), mat)
		# band clamps where one part meets the next, and two straps round the canister
		if pipe.kind in ["catalyst", "mid", "muffler"]:
			_clamp(pipe.pts[0], pipe.pts[1], pipe.radii[0], clamp_mat)
		if pipe.kind == "muffler":
			var axis: Vector3 = (pipe.pts[-1] - pipe.pts[0]).normalized()
			for s in [0.3, 0.72]:
				_clamp(pipe.pts[0].lerp(pipe.pts[-1], s), pipe.pts[0].lerp(pipe.pts[-1], s) + axis, pipe.radii[2] * 1.04, clamp_mat, 0.14)


func _add_mesh(mesh: Mesh, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)


# A short ring around a pipe at `at`, along the direction from `at` toward `toward`.
func _clamp(at: Vector3, toward: Vector3, radius: float, mat: Material, width := 0.1) -> void:
	var dir := (toward - at).normalized()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 1.12
	mesh.bottom_radius = radius * 1.12
	mesh.height = width
	mesh.radial_segments = SEGMENTS
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at + dir * width * 0.5
	mi.quaternion = Quaternion(Vector3.UP, dir)
	add_child(mi)


# Sweeps a circle along the path with the given radius at each point, with flat caps when asked.
static func _tube(pts: PackedVector3Array, radii: PackedFloat32Array, capped: bool) -> ArrayMesh:
	var n := pts.size()
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var normal := Vector3.ZERO
	var frames: Array[Basis] = []
	for i in n:
		var a := pts[maxi(i - 1, 0)]
		var b := pts[mini(i + 1, n - 1)]
		var t := (b - a).normalized()
		if i == 0:
			normal = t.cross(Vector3.UP if absf(t.y) < 0.9 else Vector3.RIGHT).normalized()
		else:
			normal = (normal - t * normal.dot(t)).normalized() # carried along the path without twisting
		frames.append(Basis(normal, t.cross(normal), t))
	for i in n:
		var f := frames[i]
		for k in SEGMENTS:
			var ang := TAU * k / SEGMENTS
			var out := f.x * cos(ang) + f.y * sin(ang)
			verts.append(pts[i] + out * radii[i])
			normals.append(out)
	for i in n - 1:
		for k in SEGMENTS:
			var k2 := (k + 1) % SEGMENTS
			var a := i * SEGMENTS + k
			var b := i * SEGMENTS + k2
			var c := (i + 1) * SEGMENTS + k
			var d := (i + 1) * SEGMENTS + k2
			indices.append_array([a, b, c, b, d, c])
	if capped:
		for end: int in [0, n - 1]:
			var centre := verts.size()
			var axis: Vector3 = frames[end].z * (-1.0 if end == 0 else 1.0)
			verts.append(pts[end])
			normals.append(axis)
			for k in SEGMENTS:
				var ring := end * SEGMENTS + k
				var ring2 := end * SEGMENTS + (k + 1) % SEGMENTS
				verts.append(verts[ring])
				normals.append(axis)
				verts.append(verts[ring2])
				normals.append(axis)
				if end == 0:
					indices.append_array([centre, verts.size() - 1, verts.size() - 2])
				else:
					indices.append_array([centre, verts.size() - 2, verts.size() - 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _metal(c: Color, rough: float, metallic: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metallic
	m.cull_mode = BaseMaterial3D.CULL_DISABLED # the winding of a swept tube is easy to get backwards, draw both sides
	return m
