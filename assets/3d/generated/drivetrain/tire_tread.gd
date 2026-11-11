extends RefCounted

# Lightweight visual tread marks follow the torus surface; no grip is implied.
static func add_to(wheel: Node3D, radius: float, rim_radius: float, width: float, count: int = 48) -> void:
	var section := (radius - rim_radius) * 0.5
	if section <= 0.0 or width <= 0.0:
		return
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	# Two angled strips per block form a shallow chevron over the crown.
	for i in count:
		var theta := TAU * i / count
		for side in [-1.0, 1.0]:
			var x0: float = side * width * 0.03
			var x1: float = side * width * 0.36
			var a0 := theta
			var a1 := theta + 0.045
			for segment in 8:
				var t0 := float(segment) / 8.0
				var t1 := float(segment + 1) / 8.0
				var start := vertices.size()
				for point in [Vector2(lerpf(x0, x1, t0), lerpf(a0, a1, t0) - 0.012), Vector2(lerpf(x0, x1, t1), lerpf(a0, a1, t1) - 0.012), Vector2(lerpf(x0, x1, t0), lerpf(a0, a1, t0) + 0.012), Vector2(lerpf(x0, x1, t1), lerpf(a0, a1, t1) + 0.012)]:
					var normalized_x := clampf(point.x / (width * 0.5), -0.99, 0.99)
					var surface_radius := radius - section + section * sqrt(1.0 - normalized_x * normalized_x) + 0.012
					vertices.append(Vector3(point.x, cos(point.y) * surface_radius, sin(point.y) * surface_radius))
				indices.append_array([start, start + 1, start + 2, start + 2, start + 1, start + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.018, 0.019, 0.021)
	material.roughness = 1.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var tread := MeshInstance3D.new()
	tread.name = "Tread"
	tread.mesh = mesh
	tread.material_override = material
	wheel.add_child(tread)
