class_name Clutch
extends Node3D

# Visual clutch pack on the right end of the crankshaft: basket, friction and steel plates,
# pressure plate, springs and lever. Its state follows EngineSim.clutch_engage:
# 1 = springs pressing the plates together, 0 = lever pulled, pressure plate lifted.

const BASKET_RADIUS := 0.5 # scene units, 5 cm
const PLATE_RADIUS := 0.42
const FRICTION_PLATES := 5
const SPRING_COUNT := 6
const LIFT := 0.02 # illustrative axial travel; not a measured factory value

var _basket: Node3D # turns with the crank
var _pressure: Node3D # slides along the shaft
var _springs: Array[MeshInstance3D] = []
var _release_rod: Node3D


# centre: the crank centre, from EngineModel. The pack sits on the end of the gearbox mainshaft, just outboard of the
# primary gear at primary_x. Its size comes from the clutch constants in EngineSim: five friction plates, six springs.
func build(centre: Vector3, spec: EngineSpec, primary_x: float) -> void:
	for c in get_children():
		c.queue_free()
	_springs.clear()
	var steel := _mat(Color(0.45, 0.45, 0.48), 0.4)
	var dark := _mat(Color(0.2, 0.2, 0.22), 0.6)
	var cork := _mat(Color(0.55, 0.4, 0.25), 0.9)
	var spring_mat := _mat(Color(0.7, 0.7, 0.72), 0.3)

	var main := GearboxModel.mainshaft_position(centre, spec)
	position = Vector3(primary_x - 0.15, main.y, main.z) # left end of the mainshaft, so the chain can run on the right
	_basket = Node3D.new()
	add_child(_basket)
	_add_disc(_basket, BASKET_RADIUS, 0.035, dark, -0.075)
	# Basket fingers surround the friction-plate tabs while leaving the pack visible.
	for i in 12:
		var angle := TAU * i / 12.0
		var finger := MeshInstance3D.new()
		var shape := BoxMesh.new()
		shape.size = Vector3(0.17, 0.09, 0.075)
		finger.mesh = shape
		finger.material_override = dark
		finger.position = Vector3(0.0, cos(angle) * 0.46, sin(angle) * 0.46)
		finger.rotation.x = angle
		_basket.add_child(finger)
	_add_disc(_basket, PLATE_RADIUS * 0.55, 0.18, steel, 0.0) # inner hub

	# friction plates (cork) alternate with steel plates across the basket
	for i in FRICTION_PLATES:
		var x := -0.04 + i * 0.02
		_add_disc(_basket, PLATE_RADIUS, 0.01, cork, x)
		_add_disc(_basket, PLATE_RADIUS * 0.96, 0.01, steel, x + 0.01)

	_pressure = Node3D.new()
	_basket.add_child(_pressure)
	_add_disc(_pressure, BASKET_RADIUS * 0.9, 0.04, steel, 0.06)

	# Shared helical mesh keeps all six visible coils in one reusable resource.
	var coil_mesh := _coil_mesh()
	for k in SPRING_COUNT:
		var a := TAU * k / SPRING_COUNT
		var spring := MeshInstance3D.new()
		spring.name = "Spring%d" % (k + 1)
		spring.mesh = coil_mesh
		spring.material_override = spring_mat
		spring.position = Vector3(0.13, 0.36 * cos(a), 0.36 * sin(a))
		_basket.add_child(spring)
		_springs.append(spring)
		var bolt := MeshInstance3D.new()
		var bolt_mesh := CylinderMesh.new()
		bolt_mesh.top_radius = 0.038
		bolt_mesh.bottom_radius = 0.038
		bolt_mesh.height = 0.025
		bolt_mesh.radial_segments = 6
		bolt.mesh = bolt_mesh
		bolt.material_override = steel
		bolt.rotation.z = PI / 2.0
		bolt.position = Vector3(0.19, 0.36 * cos(a), 0.36 * sin(a))
		_basket.add_child(bolt)

	# A representative pushrod passes through the input shaft and lifts the plate.
	_release_rod = Node3D.new()
	add_child(_release_rod)
	_add_disc(_release_rod, 0.045, 0.32, spring_mat, -0.09)
	_add_disc(_release_rod, 0.085, 0.025, steel, 0.075)


# crank_deg: 0..720 crank angle. engage: 0..1 from EngineSim.clutch_engage.
func update(crank_deg: float, engage: float) -> void:
	if _basket == null:
		return
	_basket.rotation.x = deg_to_rad(crank_deg)
	var lift := LIFT * (1.0 - clampf(engage, 0.0, 1.0))
	_pressure.position.x = lift
	for spring in _springs:
		spring.scale.x = 1.0 - lift / 0.1
		spring.position.x = 0.13 + lift * 0.5
	_release_rod.position.x = lift


func _add_disc(parent: Node3D, radius: float, width: float, mat: Material, x: float) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = width
	mesh.radial_segments = 24
	var disc := MeshInstance3D.new()
	disc.mesh = mesh
	disc.material_override = mat
	disc.position = Vector3(x, 0.0, 0.0)
	disc.rotation.z = PI / 2.0
	parent.add_child(disc)


static func _coil_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var turns := 4.0
	var segments := 48
	var sides := 6
	for i in segments:
		for j in sides:
			for pair in [Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i, j + 1), Vector2i(i, j + 1), Vector2i(i + 1, j), Vector2i(i + 1, j + 1)]:
				var phase := TAU * turns * float(pair.x) / segments
				var around := TAU * float(pair.y) / sides
				var ring := 0.03 + 0.006 * cos(around)
				surface.add_vertex(Vector3(-0.05 + 0.1 * float(pair.x) / segments + 0.006 * sin(around), ring * cos(phase), ring * sin(phase)))
	surface.generate_normals()
	return surface.commit()


static func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m
