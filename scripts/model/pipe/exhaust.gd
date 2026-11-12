class_name Exhaust
extends Node3D

# Draws an ExhaustLayout: header pipes, collector, catalytic converter, mid pipe, muffler and tailpipe.

const SEGMENTS := 20 # sides around each tube
const WALL := 0.012 # scene units, 1.2 mm: the wall of the steel tube, so an open pipe end shows a rim and a bore
# What each part is made of, for the heat glow: the header and collector are plain steel, the catalyst and canister are
# stainless, the chrome tail trim needs more heat before it shows anything. ExhaustHeat has the thresholds.
const PART_MATERIAL := {"primary": "steel", "secondary": "steel", "collector": "steel", "catalyst": "stainless",
	"mid": "steel", "muffler": "stainless", "tail": "chrome"}
# How much of the port gas temperature survives to each part: the gas cools as it goes down the system.
const HEAT_ALONG := {"primary": 1.0, "secondary": 1.0, "collector": 0.92, "catalyst": 0.8, "mid": 0.72,
	"muffler": 0.55, "tail": 0.45}
const GLOW_BOOST := 2.5 # emission multiplier on top of the colour, for a glow that reads at camera distance

var _heat: Array[ExhaustHeat] = [] # one wall temperature per drawn part
var _heat_mats: Array[StandardMaterial3D] = [] # that part's own material, so each pipe glows on its own
var _heat_parts: Array[String] = []


func build(layout: ExhaustLayout, muffler_scene: PackedScene = null) -> void:
	for c in get_children():
		c.queue_free()
	_heat.clear()
	_heat_mats.clear()
	_heat_parts.clear()
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
		# each part gets its own copy of the metal, because the glow is per part: a header at 700 C and a tail at 300 C
		# cannot share one material
		if mat is StandardMaterial3D:
			mat = (mat as StandardMaterial3D).duplicate()
		_heat.append(ExhaustHeat.new(PART_MATERIAL.get(pipe.kind, "steel")))
		_heat_mats.append(mat)
		_heat_parts.append(pipe.kind)
		var used_asset := false
		if pipe.kind == "muffler" and muffler_scene != null:
			var authored := muffler_scene.instantiate()
			if authored is Node3D:
				authored.name = "AuthoredMuffler"
				authored.position = pipe.pts[0]
				authored.quaternion = Quaternion(Vector3.UP, (pipe.pts[-1] - pipe.pts[0]).normalized())
				add_child(authored)
				used_asset = true
			else:
				authored.free()
				push_warning("Muffler scene must have a Node3D root")
		if not used_asset:
			_add_mesh(_tube(pipe.pts, pipe.radii, pipe.kind == "muffler", WALL), mat)
		# the hardware the assembly is bolted together with
		if pipe.kind == "primary" and pipe.pts.size() >= 2:
			var out_dir: Vector3 = (pipe.pts[1] - pipe.pts[0]).normalized()
			_flange(pipe.pts[0], out_dir, pipe.radii[0], "Flange_%s" % pipe.name.trim_prefix("primary "), header, clamp_mat)
		if pipe.kind in ["collector", "muffler"] and pipe.pts.size() >= 2:
			var joint_axis: Vector3 = (pipe.pts[1] - pipe.pts[0]).normalized()
			var joint_tangent := joint_axis.cross(Vector3.UP).normalized()
			if joint_tangent.length() < 0.1:
				joint_tangent = joint_axis.cross(Vector3.RIGHT).normalized()
			for s in 2:
				var joint_side := 1.0 if s == 0 else -1.0
				_spring(pipe.pts[0] + joint_tangent * joint_side * pipe.radii[0] * 1.3, joint_axis,
					pipe.radii[0] * 0.22, "%sSpring%d" % [pipe.kind.capitalize(), s], clamp_mat)
		# band clamps where one part meets the next, and two straps round the canister
		if pipe.kind in ["catalyst", "mid", "muffler"]:
			_clamp(pipe.pts[0], pipe.pts[1], pipe.radii[0], clamp_mat)
		if pipe.kind == "muffler":
			var axis: Vector3 = (pipe.pts[-1] - pipe.pts[0]).normalized()
			for s in [0.3, 0.72]:
				_clamp(pipe.pts[0].lerp(pipe.pts[-1], s), pipe.pts[0].lerp(pipe.pts[-1], s) + axis, pipe.radii[2] * 1.04, clamp_mat, 0.14)
			# the hanger: a stay from the top of the canister up to a bracket on the frame, with a rubber bobbin so the
			# exhaust can move without cracking. The anchor is ESTIMATE - inboard and above the canister, where a
			# subframe rail runs; the exhaust node has no reference to the frame to hang it off properly.
			var middle: Vector3 = pipe.pts[0].lerp(pipe.pts[-1], 0.55)
			var top: Vector3 = middle + Vector3(0.0, pipe.radii[2] * 0.95, 0.0)
			var upward := Vector3(0.0, 0.45, 0.0)
			var hanger := Node3D.new()
			hanger.name = "MufflerHanger"
			hanger.position = top
			add_child(hanger)
			var stay := MeshInstance3D.new()
			stay.name = "Stay"
			var rod := CylinderMesh.new()
			rod.top_radius = 0.035
			rod.bottom_radius = 0.035
			rod.height = upward.length()
			rod.radial_segments = 8
			stay.mesh = rod
			stay.material_override = clamp_mat
			stay.position = upward * 0.5
			stay.quaternion = Quaternion(Vector3.UP, upward.normalized())
			hanger.add_child(stay)
			var bobbin := MeshInstance3D.new()
			bobbin.name = "Bobbin"
			var rubber := CylinderMesh.new()
			rubber.top_radius = 0.075
			rubber.bottom_radius = 0.075
			rubber.height = 0.10
			rubber.radial_segments = 12
			bobbin.mesh = rubber
			bobbin.material_override = _metal(Color(0.12, 0.12, 0.13), 0.9, 0.0)
			bobbin.position = upward
			bobbin.quaternion = Quaternion(Vector3.UP, upward.normalized())
			hanger.add_child(bobbin)

	# the lambda sensor: a boss welded into the collector with the sensor threaded into it and a wire leaving along the
	# pipe. The physics already reads lambda; this is the part that measures it.
	for pipe in layout.pipes:
		if pipe.kind == "collector" and pipe.pts.size() >= 2:
			var n_axis: Vector3 = (pipe.pts[1] - pipe.pts[0]).normalized()
			var n_out := n_axis.cross(Vector3.RIGHT).normalized()
			if n_out.length() < 0.1:
				n_out = n_axis.cross(Vector3.UP).normalized()
			var boss := Node3D.new()
			boss.name = "LambdaBoss"
			boss.position = pipe.pts[1] + n_out * pipe.radii[1] * 0.9
			boss.quaternion = Quaternion(Vector3.UP, n_out)
			add_child(boss)
			var collar := MeshInstance3D.new()
			collar.name = "Collar"
			var collar_mesh := CylinderMesh.new()
			collar_mesh.top_radius = 0.07
			collar_mesh.bottom_radius = 0.07
			collar_mesh.height = 0.12
			collar_mesh.radial_segments = 6
			collar.mesh = collar_mesh
			collar.material_override = clamp_mat
			boss.add_child(collar)
			var sensor := MeshInstance3D.new()
			sensor.name = "Sensor"
			var sensor_mesh := CylinderMesh.new()
			sensor_mesh.top_radius = 0.045
			sensor_mesh.bottom_radius = 0.045
			sensor_mesh.height = 0.30
			sensor_mesh.radial_segments = 10
			sensor.mesh = sensor_mesh
			sensor.material_override = cat
			sensor.position = Vector3(0.0, 0.16, 0.0)
			boss.add_child(sensor)
			var wire := MeshInstance3D.new()
			wire.name = "Wire"
			wire.mesh = _tube(PackedVector3Array([
				pipe.pts[1] + n_out * 0.30,
				pipe.pts[1] + n_out * 0.36 + n_axis * 0.25,
				pipe.pts[1] + n_out * 0.20 + n_axis * 0.55]), PackedFloat32Array([0.014, 0.014, 0.014]), false)
			wire.material_override = clamp_mat
			add_child(wire)
			break

	# the catalyst gets a shield, as every real one does
	for pipe in layout.pipes:
		if pipe.kind == "catalyst" and pipe.pts.size() >= 2:
			_shield(pipe.pts, pipe.radii[0], 0.06, muffler, "CatalystShield")
			break


# Feeds the heat glow from the simulation's exhaust temperature, once per frame. Only a wall past its material's
# threshold glows, and it takes seconds of hot running to get there: a cold pipe draws nothing.
func update_heat(gas_c: float, delta: float) -> void:
	for i in _heat.size():
		var along: float = HEAT_ALONG.get(_heat_parts[i], 1.0)
		_heat[i].step(gas_c * along, delta)
		var g: Dictionary = _heat[i].glow()
		var strength := float(g.strength)
		var mat := _heat_mats[i]
		if mat == null:
			continue
		mat.emission_enabled = strength > 0.0
		if strength > 0.0:
			mat.emission = g.colour
			mat.emission_energy_multiplier = 1.0 + GLOW_BOOST * pow(strength, 1.6)


# What a test (or a HUD) can ask: the wall temperature of part i, and whether it is glowing.
func part_wall_c(i: int) -> float:
	return _heat[i].wall_c if i >= 0 and i < _heat.size() else 0.0


func part_glow(i: int) -> float:
	return float(_heat[i].glow().strength) if i >= 0 and i < _heat.size() else 0.0


func part_count() -> int:
	return _heat.size()


func _add_mesh(mesh: Mesh, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)


# The flange a header bolts to the head with, with its crush gasket and two studs. A real one is an 8-10 mm steel plate
# the tube is welded through, and the pipe's own radius sets its size: ESTIMATE the plate at 1.9x the tube radius.
#   port  the exhaust port, i.e. pipe.pts[0]
#   dir   the direction the pipe leaves the port in
func _flange(port: Vector3, dir: Vector3, radius: float, plate_name: String, steel: Material, dark: Material) -> void:
	var node := Node3D.new()
	node.name = plate_name
	node.position = port
	add_child(node)
	var plate := CylinderMesh.new()
	plate.top_radius = radius * 1.9
	plate.bottom_radius = radius * 1.9
	plate.height = 0.10 # 10 mm plate
	plate.radial_segments = SEGMENTS
	var body := MeshInstance3D.new()
	body.name = "Plate"
	body.mesh = plate
	body.material_override = steel
	body.quaternion = Quaternion(Vector3.UP, dir)
	node.add_child(body)
	# the crush gasket, a ring of copper between plate and head
	var gasket := MeshInstance3D.new()
	gasket.name = "Gasket"
	var ring := TorusMesh.new()
	ring.inner_radius = radius * 1.05
	ring.outer_radius = radius * 1.7
	ring.rings = SEGMENTS
	ring.ring_segments = 8
	gasket.mesh = ring
	gasket.material_override = _metal(Color(0.72, 0.45, 0.25), 0.5, 0.6)
	gasket.quaternion = Quaternion(Vector3.UP, dir)
	gasket.position = -dir * 0.06
	node.add_child(gasket)
	# two studs either side of the tube, each with its nut
	var tangent := dir.cross(Vector3.UP).normalized()
	if tangent.length() < 0.1:
		tangent = dir.cross(Vector3.RIGHT).normalized()
	for i in 2:
		var side := 1.0 if i == 0 else -1.0
		var stud := MeshInstance3D.new()
		stud.name = "Stud%d" % i
		var rod := CylinderMesh.new()
		rod.top_radius = 0.035
		rod.bottom_radius = 0.035
		rod.height = 0.26
		rod.radial_segments = 8
		stud.mesh = rod
		stud.material_override = steel
		stud.position = tangent * side * radius * 1.55 + dir * 0.10
		stud.quaternion = Quaternion(Vector3.UP, dir)
		node.add_child(stud)
		var nut := MeshInstance3D.new()
		nut.name = "Nut"
		var hex := CylinderMesh.new()
		hex.top_radius = 0.055
		hex.bottom_radius = 0.055
		hex.height = 0.07
		hex.radial_segments = 6 # a hex nut, not a round one
		nut.mesh = hex
		nut.material_override = dark
		nut.position = dir * 0.14
		stud.add_child(nut)


# A tension spring across a slip joint, hooked to a lug on each pipe. The helix is swept with _tube so the coils read as
# round wire from any angle.
func _spring(at: Vector3, axis: Vector3, radius: float, spring_name: String, steel: Material, coils := 6) -> void:
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	var flat := axis.cross(Vector3.UP).normalized()
	if flat.length() < 0.1:
		flat = axis.cross(Vector3.RIGHT).normalized()
	var up := axis.cross(flat).normalized()
	var steps := coils * 12
	for i in steps:
		var t := float(i) / float(steps - 1)
		var a := coils * TAU * t
		pts.append(at + axis * (t * 0.22) + flat * cos(a) * radius + up * sin(a) * radius)
		radii.append(0.012) # 12 mm of wire
	var node := MeshInstance3D.new()
	node.name = spring_name
	node.mesh = _tube(pts, radii, false)
	node.material_override = steel
	add_child(node)


# A half-cylindrical heat shield over a pipe, standing `stand_off` clear of it so air can pass behind.
func _shield(pts: PackedVector3Array, radius: float, stand_off: float, steel: Material, shield_name: String) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var axis := (pts[1] - pts[0]).normalized()
	var up := Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var side := axis.cross(up).normalized()
	var out := side.cross(axis).normalized()
	var r := radius + stand_off
	var steps := 12
	for i in steps:
		var a0 := lerpf(-PI * 0.45, PI * 0.45, float(i) / float(steps))
		var a1 := lerpf(-PI * 0.45, PI * 0.45, float(i + 1) / float(steps))
		var n0 := (out * cos(a0) + side * sin(a0)).normalized()
		var n1 := (out * cos(a1) + side * sin(a1)).normalized()
		var p := pts[0] + n0 * r
		var q := pts[1] + n0 * r
		var s := pts[0] + n1 * r
		var t := pts[1] + n1 * r
		for item in [[p, n0], [q, n0], [s, n1], [s, n1], [q, n0], [t, n1]]:
			surface.set_normal(item[1])
			surface.add_vertex(item[0])
	var node := MeshInstance3D.new()
	node.name = shield_name
	node.mesh = surface.commit()
	node.material_override = steel
	add_child(node)


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


# Sweeps a circle along the path with the given radius at each point, with flat caps when asked. An uncapped tube is
# hollow: the last segment gets an inner liner a wall thick and the mouth gets a rim, so the outlet reads as pipe, not
# as a paper edge.
static func _tube(pts: PackedVector3Array, radii: PackedFloat32Array, capped: bool, wall := 0.0) -> ArrayMesh:
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
	# an open end is a hole: give it a wall, an inner liner over the last segment and a rim at the mouth
	if wall > 0.0 and not capped and n > 1:
		var liner := verts.size()
		for i in [n - 2, n - 1]:
			var f := frames[i]
			for k in SEGMENTS:
				var ang := TAU * k / SEGMENTS
				var out := f.x * cos(ang) + f.y * sin(ang)
				verts.append(pts[i] + out * maxf(radii[i] - wall, radii[i] * 0.5))
				normals.append(-out) # the liner faces the bore
		for k in SEGMENTS:
			var k2 := (k + 1) % SEGMENTS
			var a := liner + k
			var b := liner + k2
			var c := liner + SEGMENTS + k
			var d := liner + SEGMENTS + k2
			indices.append_array([a, c, b, b, c, d])
		var rim := verts.size()
		var f_end := frames[n - 1]
		var axis: Vector3 = f_end.z
		for k in SEGMENTS:
			var ang := TAU * k / SEGMENTS
			var out := f_end.x * cos(ang) + f_end.y * sin(ang)
			verts.append(pts[n - 1] + out * radii[n - 1])
			normals.append(axis)
			verts.append(pts[n - 1] + out * maxf(radii[n - 1] - wall, radii[n - 1] * 0.5))
			normals.append(axis)
		for k in SEGMENTS:
			var k2 := (k + 1) % SEGMENTS
			var a := rim + k * 2
			var b := a + 1
			var c := rim + k2 * 2
			var d := c + 1
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
