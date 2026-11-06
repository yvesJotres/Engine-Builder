class_name Clutch
extends Node3D

# Visual clutch pack on the right end of the crankshaft: basket, friction and steel plates,
# pressure plate, springs and lever. Its state follows EngineSim.clutch_engage:
# 1 = springs pressing the plates together, 0 = lever pulled, pressure plate lifted.

const BASKET_RADIUS := 0.5 # scene units, 5 cm
const PLATE_RADIUS := 0.42
const FRICTION_PLATES := 5
const SPRING_COUNT := 6
const LIFT := 0.05 # how far the pressure plate lifts when the lever is pulled

var _basket: Node3D # turns with the crank
var _pressure: Node3D # slides along the shaft
var _springs: Array[MeshInstance3D] = []
var _lever: Node3D


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
	_add_disc(_basket, BASKET_RADIUS, 0.12, dark, 0.0)

	# friction plates (cork) alternate with steel plates across the basket
	for i in FRICTION_PLATES:
		var x := -0.04 + i * 0.02
		_add_disc(_basket, PLATE_RADIUS, 0.01, cork, x)
		_add_disc(_basket, PLATE_RADIUS * 0.96, 0.01, steel, x + 0.01)

	_pressure = Node3D.new()
	_basket.add_child(_pressure)
	_add_disc(_pressure, BASKET_RADIUS * 0.9, 0.04, steel, 0.06)

	# coil springs around the pressure plate, between the basket and the plate
	for k in SPRING_COUNT:
		var a := TAU * k / SPRING_COUNT
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.012
		mesh.bottom_radius = 0.012
		mesh.height = 0.1
		var spring := MeshInstance3D.new()
		spring.mesh = mesh
		spring.material_override = spring_mat
		spring.position = Vector3(0.03, 0.36 * cos(a), 0.36 * sin(a))
		spring.rotation.z = PI / 2.0
		_pressure.add_child(spring)
		_springs.append(spring)

	# clutch lever at the edge of the basket, pivoting on the cover
	_lever = Node3D.new()
	_lever.position = Vector3(0.1, BASKET_RADIUS, 0.0)
	add_child(_lever)
	var arm := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.05, 0.4, 0.05)
	arm.mesh = box
	arm.material_override = steel
	arm.position = Vector3(0.0, 0.2, 0.0)
	_lever.add_child(arm)


# crank_deg: 0..720 crank angle. engage: 0..1 from EngineSim.clutch_engage.
func update(crank_deg: float, engage: float) -> void:
	if _basket == null:
		return
	_basket.rotation.x = deg_to_rad(crank_deg)
	_pressure.position.x = -LIFT * (1.0 - engage)
	for spring in _springs:
		spring.scale.y = lerpf(0.6, 1.0, engage) # springs compress as the lever is pulled
	_lever.rotation.z = (1.0 - engage) * 0.6


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


static func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m
