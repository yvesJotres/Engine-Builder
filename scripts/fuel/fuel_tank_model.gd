class_name FuelTankModel
extends Node3D

# Tank above the engine. Its shape and bounding dimensions are visual estimates, not a measured internal volume.

const BASE_SIZE := Vector3(2.3, 1.45, 3.6) # scene units, 12 L

var size := BASE_SIZE * pow(FuelTank.TANK_LITRES / 12.0, 1.0 / 3.0)

var _level: MeshInstance3D
var _level_mesh: CylinderMesh
var _level_material: StandardMaterial3D
var _bottom := 0.0
var _size_factor := 1.0


func _ready() -> void:
	_bottom = -size.y * 0.2
	var shell := MeshInstance3D.new()
	shell.name = "TankShell"
	shell.mesh = _tank_mesh()
	var paint := _mat(Color(0.52, 0.1, 0.11), 0.36, false)
	paint.metallic = 0.15
	shell.material_override = paint
	add_child(shell)

	var cap := MeshInstance3D.new()
	var cap_mesh := CylinderMesh.new()
	cap_mesh.top_radius = size.x * 0.16
	cap_mesh.bottom_radius = size.x * 0.16
	cap_mesh.height = 0.05
	cap.mesh = cap_mesh
	cap.material_override = _mat(Color(0.24, 0.25, 0.27), 0.35, false)
	cap.position = Vector3(0.0, size.y * 0.42, size.z * 0.06)
	add_child(cap)
	cap.name = "FillerCap"
	for i in 6:
		var bolt := MeshInstance3D.new()
		var bolt_mesh := CylinderMesh.new()
		bolt_mesh.top_radius = 0.018
		bolt_mesh.bottom_radius = 0.018
		bolt_mesh.height = 0.012
		bolt_mesh.radial_segments = 8
		bolt.mesh = bolt_mesh
		bolt.material_override = _mat(Color(0.65, 0.65, 0.67), 0.4, false)
		var a := TAU * i / 6.0
		bolt.position = cap.position + Vector3(cos(a) * size.x * 0.12, 0.032, sin(a) * size.x * 0.12)
		add_child(bolt)
	var outlet := MeshInstance3D.new()
	outlet.name = "TankOutlet"
	var fitting := CylinderMesh.new()
	fitting.top_radius = 0.095
	fitting.bottom_radius = 0.065
	fitting.height = 0.14
	outlet.mesh = fitting
	outlet.material_override = _mat(Color(0.36, 0.37, 0.39), 0.4, false)
	outlet.position = Vector3(0, -size.y * 0.46, -size.z * 0.12)
	add_child(outlet)

	var gauge := MeshInstance3D.new()
	var gauge_mesh := CylinderMesh.new()
	gauge_mesh.top_radius = 0.035
	gauge_mesh.bottom_radius = 0.035
	gauge_mesh.height = size.y * 0.3
	gauge.mesh = gauge_mesh
	gauge.material_override = _mat(Color(0.09, 0.1, 0.11), 0.5, false)
	gauge.position = Vector3(-size.x * 0.45, -size.y * 0.05, -size.z * 0.2)
	add_child(gauge)
	_level_mesh = CylinderMesh.new()
	_level_mesh.top_radius = 0.02
	_level_mesh.bottom_radius = 0.02
	_level = MeshInstance3D.new()
	_level.mesh = _level_mesh
	_level_material = _mat(Color(0.2, 0.4, 0.9), 0.3, false)
	_level.material_override = _level_material
	add_child(_level)


func _tank_mesh() -> ArrayMesh:
	var sections := [Vector3(-0.5, 0.12, 0.38), Vector3(-0.38, 0.65, 0.72), Vector3(-0.12, 0.95, 0.92), Vector3(0.12, 1.0, 0.85), Vector3(0.34, 0.72, 0.68), Vector3(0.5, 0.16, 0.35)]
	var rings: Array[PackedVector3Array] = []
	for section in sections:
		var ring := PackedVector3Array()
		for vertex in 16:
			var angle := TAU * vertex / 16.0
			ring.append(Vector3(cos(angle) * size.x * 0.5 * section.y, sin(angle) * size.y * 0.5 * section.z, section.x * size.z))
		rings.append(ring)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for section_index in rings.size() - 1:
		for vertex in 16:
			var next := (vertex + 1) % 16
			for point in [rings[section_index][vertex], rings[section_index][next], rings[section_index + 1][vertex], rings[section_index][next], rings[section_index + 1][next], rings[section_index + 1][vertex]]:
				surface.add_vertex(point)
	for vertex in 16:
		var next := (vertex + 1) % 16
		for point in [Vector3(0.0, 0.0, -size.z * 0.5), rings[0][next], rings[0][vertex], Vector3(0.0, 0.0, size.z * 0.5), rings[-1][vertex], rings[-1][next]]:
			surface.add_vertex(point)
	surface.generate_normals()
	return surface.commit()


# Puts the tank over centre_z with its underside at bottom_y.
func set_capacity(litres: float) -> void:
	_size_factor = pow(maxf(litres, 0.1) / 12.0, 1.0 / 3.0)
	scale = Vector3.ONE * _size_factor


func place(bottom_y: float, centre_z: float) -> void:
	position = Vector3(0.0, bottom_y + size.y * 0.46 * _size_factor, centre_z)


func outlet_position() -> Vector3:
	return position + Vector3(0.0, (-size.y * 0.46 - 0.07) * _size_factor, -size.z * 0.12 * _size_factor)

# fraction: 0 to 1 of the tank full. colour: fuel colour, petrol blue or E85 green.

func update(fraction: float, colour: Color) -> void:
	var h := maxf(clampf(fraction, 0.0, 1.0), 0.001) * size.y * 0.3
	_level_mesh.height = h
	_level.position = Vector3(-size.x * 0.45 - 0.025, _bottom + h * 0.5, -size.z * 0.2)
	_level_material.albedo_color = Color(0.45, 0.38, 0.22).lerp(colour, 0.15)


static func _mat(c: Color, rough: float, transparent: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if transparent:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m
