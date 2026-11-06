class_name FuelTankModel
extends Node3D

# Tank above the engine. The fuel inside rises and falls with FuelTank.fraction().
# The box holds FuelTank.TANK_LITRES (12 L): 36 x 14.5 x 23 cm at 12 L, scaled in all directions for another capacity.
# Its shape is an estimate, not taken from a drawing; place() puts it above the highest engine part.

const BASE_SIZE := Vector3(3.6, 1.45, 2.3) # scene units, 12 L

var size := BASE_SIZE * pow(FuelTank.TANK_LITRES / 12.0, 1.0 / 3.0)

var _level: MeshInstance3D
var _level_mesh: BoxMesh
var _bottom := 0.0


func _ready() -> void:
	_bottom = -size.y * 0.5
	var shell := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	shell.mesh = box
	shell.material_override = _mat(Color(0.7, 0.7, 0.75, 0.25), 0.2, true)
	add_child(shell)

	_level_mesh = BoxMesh.new()
	_level = MeshInstance3D.new()
	_level.mesh = _level_mesh
	add_child(_level)


# Puts the tank over centre_z with its underside at bottom_y.
func place(bottom_y: float, centre_z: float) -> void:
	position = Vector3(0.0, bottom_y + size.y * 0.5, centre_z)


func outlet_position() -> Vector3:
	return position + Vector3(0.0, -size.y * 0.5, 0.0)

# fraction: 0 to 1 of the tank full. colour: fuel colour, petrol blue or E85 green.

func update(fraction: float, colour: Color) -> void:
	var h := maxf(fraction, 0.001) * size.y
	_level_mesh.size = Vector3(size.x * 0.96, h, size.z * 0.96)
	_level.position = Vector3(0.0, _bottom + h * 0.5, 0.0)
	_level.material_override = _mat(colour, 0.3, false)


static func _mat(c: Color, rough: float, transparent: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if transparent:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m
