class_name BackfireFlame
extends Node3D

# A backfire is a deflagration at the tailpipe mouth: a short, bright flash about a pipe diameter across, gone in a few
# tens of milliseconds. Its size and its light come from the energy the cylinder actually released (Cylinder.backfire_j),
# so a 300 J bang on a litre four reads as a ball and a 30 J tick on a 125 as a flicker. Visual only - the energy, the
# moment and the gating are the cylinder's; this draws it where it happens.
#
# Units follow the project: 1 scene unit = 10 cm, so the radii below are in scene units.

const POP_SECONDS := 0.09 # s, the flash is visible for this long
const REFERENCE_J := 300.0 # J, the pop that fills MAX_RADIUS
const MIN_RADIUS := 0.05 # a weak pop still shows this much
const MAX_RADIUS := 0.22 # about a pipe diameter out of the outlet
const LIGHT_ENERGY := 4.0 # OmniLight3D energy at REFERENCE_J
const FLAME_COLOUR := Color(1.0, 0.62, 0.22) # orange-white, a fuel flame rather than a blue one

var _mesh: MeshInstance3D
var _light: OmniLight3D
var _material: StandardMaterial3D
var _left := 0.0
var _radius := MIN_RADIUS


func build() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_color = FLAME_COLOUR
	_material.emission_enabled = true
	_material.emission = FLAME_COLOUR
	_material.emission_energy_multiplier = 3.0
	_mesh = MeshInstance3D.new()
	_mesh.mesh = sphere
	_mesh.material_override = _material
	_mesh.visible = false
	add_child(_mesh)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.66, 0.3)
	_light.omni_range = 3.0
	_light.light_energy = 0.0
	add_child(_light)


# The flash sits just outside the outlet and faces along the gas, so it grows out of the pipe instead of inside it.
func place(at: Vector3, out_dir: Vector3) -> void:
	var dir := out_dir.normalized() if out_dir.length() > 0.001 else Vector3.FORWARD
	if not is_inside_tree():
		position = at + dir * 0.06
		return
	global_position = at + dir * 0.06
	if dir.cross(Vector3.UP).length() > 0.001:
		look_at(global_position + dir, Vector3.UP)


func pop(energy_j: float) -> void:
	if energy_j <= 0.0:
		return
	# sqrt: four times the energy is twice the radius, which stops a 1,000 J bang from filling the screen
	var share := clampf(sqrt(energy_j / REFERENCE_J), 0.0, 1.0)
	_radius = lerpf(MIN_RADIUS, MAX_RADIUS, share)
	_left = POP_SECONDS
	if _mesh != null:
		_mesh.scale = Vector3.ONE * _radius
		_mesh.visible = true
	if _light != null:
		_light.light_energy = LIGHT_ENERGY * share


func update(delta: float) -> void:
	if _left <= 0.0:
		return
	_left = maxf(_left - maxf(delta, 0.0), 0.0)
	var fade := clampf(_left / POP_SECONDS, 0.0, 1.0)
	if _mesh != null:
		_mesh.scale = Vector3.ONE * _radius * (0.55 + 0.45 * fade)
		_mesh.visible = _left > 0.0
		_material.albedo_color.a = fade
	if _light != null:
		_light.light_energy = LIGHT_ENERGY * fade * fade * clampf(sqrt(_radius / MAX_RADIUS), 0.0, 1.0)


# What the last pop drew, for the tests: the radius in scene units.
func radius() -> float:
	return _radius


func visible_now() -> bool:
	return _mesh != null and _mesh.visible
