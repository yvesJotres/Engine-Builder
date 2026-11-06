class_name FuelLine
extends Node3D

# Fuel hose from the tank outlet to an injector on the throttle body.
# Two straight runs: along the tank's underside, then down to the injector.
# Radius and routing are estimates.

const HOSE_RADIUS := 0.03 # scene units, 3 mm
const INJECTOR_RADIUS := 0.05

var _mat_hose: StandardMaterial3D
var _mat_injector: StandardMaterial3D


func _ready() -> void:
	_mat_hose = _mat(Color(0.15, 0.15, 0.17), 0.6)
	_mat_injector = _mat(Color(0.6, 0.6, 0.65), 0.3)


# outlet: tank fuel outlet. injector: nozzle position, world coordinates.
func build(outlet: Vector3, injector: Vector3) -> void:
	for c in get_children():
		c.queue_free()
	var elbow := Vector3(injector.x, outlet.y, outlet.z)
	_tube(outlet, elbow, HOSE_RADIUS)
	_tube(elbow, injector, HOSE_RADIUS)
	_add_cyl(injector + Vector3(0.0, 0.05, 0.0), INJECTOR_RADIUS, 0.1, _mat_injector)


func _tube(a: Vector3, b: Vector3, radius: float) -> void:
	var dir := b - a
	if dir.length() < 0.0001:
		return
	var mi := _add_cyl((a + b) * 0.5, radius, dir.length(), _mat_hose)
	mi.quaternion = Quaternion(Vector3.UP, dir.normalized())


func _add_cyl(pos: Vector3, radius: float, height: float, mat: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi


static func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m
