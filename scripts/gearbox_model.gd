class_name GearboxModel
extends Node3D

# Drawn gearbox: the primary drive from the crank, then mainshaft and countershaft with every gear pair, tooth counts from Gearbox.
# The primary drive has the spec reduction (EngineSpec.primary_ratio) and sets how far the clutch sits behind the crank; the
# gearbox shafts follow behind it, and the countershaft carries the front sprocket, so the chain leaves toward the rear wheel.
# Module (tooth size) is an estimate; the tooth counts are from the catalogue.

const MODULE := 0.015 # scene units, 1.5 mm tooth module, estimate
const GEAR_WIDTH := 0.035 # scene units, estimate
const PAIR_SPACING := 0.12 # scene units between gear pairs along the shafts, estimate
const SHAFT_RADIUS := 0.03 # scene units, estimate
const SHAFT_GAP := 0.375 # scene units, centre distance = module × (main + counter) / 2
const PRIMARY_DRIVE_TEETH := 23 # crank gear, estimate; the driven gear on the clutch has teeth × primary ratio


# Teeth on the crank gear and on the clutch gear, giving the spec primary reduction.
static func primary_teeth(spec: EngineSpec) -> Vector2i:
	return Vector2i(PRIMARY_DRIVE_TEETH, roundi(PRIMARY_DRIVE_TEETH * spec.primary_ratio))


# Centre distance of the primary gears, scene units: how far the mainshaft sits behind the crank.
static func primary_distance(spec: EngineSpec) -> float:
	var t := primary_teeth(spec)
	return MODULE * (t.x + t.y) * 0.5


# Mainshaft position behind the crank, where the clutch sits. centre: crank centre in world space.
static func mainshaft_position(centre: Vector3, spec: EngineSpec) -> Vector3:
	return Vector3(0.0, centre.y, centre.z - primary_distance(spec))


# Countershaft position, further back again, where the front sprocket sits. centre: crank centre in world space.
static func countershaft_position(centre: Vector3, spec: EngineSpec) -> Vector3:
	return mainshaft_position(centre, spec) + Vector3(0.0, 0.0, -SHAFT_GAP)


# Builds the primary drive and the gearbox behind the crank. centre: crank centre in world space.
# primary_x: where the primary gear sits along the crank (the clutch is just outboard of it).
func build(centre: Vector3, spec: EngineSpec, primary_x: float) -> void:
	for c in get_children():
		c.queue_free()
	var steel := _mat(Color(0.45, 0.45, 0.48), 0.4)
	var gear_mat := _mat(Color(0.55, 0.55, 0.6), 0.35)
	var main_z := mainshaft_position(centre, spec).z
	var counter_z := countershaft_position(centre, spec).z

	# primary drive: the crank gear drives the gear on the clutch, in one plane
	var teeth := primary_teeth(spec)
	_gear(teeth.x, Vector3(primary_x, centre.y, centre.z), gear_mat)
	_gear(teeth.y, Vector3(primary_x, centre.y, main_z), gear_mat)

	# the mainshaft runs out to the clutch on the left, the countershaft out to the front sprocket on the right
	var left := primary_x - 0.25
	_shaft(Vector3((left + 0.45) * 0.5, centre.y, main_z), 0.45 - left, steel)
	var right := Drivetrain.CHAIN_X + 0.05
	_shaft(Vector3((-0.4 + right) * 0.5, centre.y, counter_z), right + 0.4, steel)
	for i in Gearbox.MAIN_TEETH.size():
		var x := -0.3 + i * PAIR_SPACING
		_gear(Gearbox.MAIN_TEETH[i], Vector3(x, centre.y, main_z), gear_mat)
		_gear(Gearbox.COUNTER_TEETH[i], Vector3(x, centre.y, counter_z), gear_mat)


# A gear with its axis along X. Teeth are cut from the pitch circle, module × teeth / 2.
func _gear(teeth: int, at: Vector3, mat: Material) -> void:
	var pitch := MODULE * teeth * 0.5
	var root := pitch - 1.25 * MODULE
	var tip := pitch + MODULE
	var step := TAU / teeth
	var pts := PackedVector2Array()
	for i in teeth:
		var a := i * step
		pts.append(Vector2.from_angle(a - 0.25 * step) * tip)
		pts.append(Vector2.from_angle(a + 0.25 * step) * tip)
		pts.append(Vector2.from_angle(a + 0.5 * step) * root)
	var csg := CSGPolygon3D.new()
	csg.polygon = pts
	csg.mode = CSGPolygon3D.MODE_DEPTH
	csg.depth = GEAR_WIDTH
	csg.material = mat
	csg.rotation.y = PI / 2.0 # extrude along X
	csg.position = at
	add_child(csg)


func _shaft(at: Vector3, length: float, mat: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = SHAFT_RADIUS
	mesh.bottom_radius = SHAFT_RADIUS
	mesh.height = length
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	mi.rotation.z = PI / 2.0 # along X
	add_child(mi)


static func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m
