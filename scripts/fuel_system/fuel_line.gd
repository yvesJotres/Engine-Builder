class_name FuelLine
extends Node3D

# Estimated external feed hose from tank outlet to the fuel rail or carburettors.

const HOSE_RADIUS := 0.03 # scene units, 3 mm
const INJECTOR_RADIUS := 0.05

var _mat_hose: StandardMaterial3D
var _mat_injector: StandardMaterial3D


func _ready() -> void:
	_mat_hose = _mat(Color(0.15, 0.15, 0.17), 0.6)
	_mat_injector = _mat(Color(0.6, 0.6, 0.65), 0.3)


# outlet: tank fuel outlet. injector: nozzle position, world coordinates.
func build(outlet: Vector3, feeds: Array[Vector3], induction: String = "injection") -> void:
	for c in get_children():
		c.queue_free()
	if feeds.is_empty():
		return
	# Injected engines share their existing rail; carburettors each need a feed.
	var junction := outlet + Vector3(0.0, -0.25, 0.0)
	_tube(outlet, junction, HOSE_RADIUS)
	var targets: Array[Vector3] = []
	if induction == "injection":
		targets.append(feeds[0])
	else:
		targets.append_array(feeds)
	for target in targets:
		var elbow := Vector3(target.x, junction.y, target.z)
		_tube(junction, elbow, HOSE_RADIUS)
		_tube(elbow, target, HOSE_RADIUS)
		var connector := _add_cyl(target, INJECTOR_RADIUS, 0.08, _mat_injector)
		connector.name = "FeedConnector"


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
