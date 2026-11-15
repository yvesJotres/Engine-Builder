class_name ExhaustFume
extends Node3D

# What comes out of the pipe, drawn from what the engine is actually doing rather than from a timer.
#
# Two things are visible on a real bike, and they are not the same substance:
#
#  1. VAPOUR - water. Petrol burns to water, and while the gas is still cool enough for it to condense (a cold start, a cold
#     morning, a low load) it shows as a white plume. It disappears once the exhaust is hot, which is why a warm bike makes
#     none: VAPOUR_TOP_K is where the plume has gone.
#  2. SOOT - unburnt carbon from an over-rich charge. Only a rich mixture makes it (lambda under SOOT_LAMBDA), and it builds
#     up while the engine stays rich before clearing, so a long rich pull smokes more than a blip.
#
# Both are scaled by the mass flow the pipes are carrying, so a shut throttle makes nothing and 5,000 rpm makes more than idle.
# Units follow the project: 1 scene unit = 10 cm.

const AMOUNT_MAX := 96 # particles in the emitter, the pool the density is drawn from
const VAPOUR_FULL_K := 550.0 # K, at or below this the plume is at full density
const VAPOUR_TOP_K := 900.0 # K, above this the exhaust is dry and there is no plume
const SOOT_LAMBDA := 0.75 # below this the charge is rich enough to make visible carbon
const SOOT_BUILD_TAU := 3.0 # s to reach full soot while rich
const SOOT_CLEAR_TAU := 6.0 # s to clear it again once the mixture is back
const FLOW_REFERENCE := 0.05 # kg/s, the flow that counts as "a lot" for a 1 L four at high load
const MIN_FLOW := 0.001 # kg/s, below this the engine is not running: nothing to show
const VAPOUR_COLOUR := Color(0.92, 0.93, 0.95)
const SOOT_COLOUR := Color(0.18, 0.17, 0.16)

var _particles: GPUParticles3D
var _material: StandardMaterial3D
var _vapour := 0.0 # 0..1, how much of the plume is water vapour
var _soot := 0.0 # 0..1, how much carbon is in the plume
var _density := 0.0 # 0..1, particles on screen
var _flow_share := 0.0 # 0..1, mass flow against FLOW_REFERENCE


func build() -> void:
	_particles = GPUParticles3D.new()
	_particles.amount = AMOUNT_MAX
	_particles.lifetime = 1.6
	_particles.local_coords = false
	_particles.emitting = false
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.03
	process.direction = Vector3(0.0, 0.0, -1.0)
	process.spread = 9.0
	process.initial_velocity_min = 0.6
	process.initial_velocity_max = 1.6
	process.gravity = Vector3(0.0, 0.05, 0.0) # warm gas lifts a little before it cools
	process.damping_min = 0.5
	process.damping_max = 1.1
	process.scale_min = 0.5
	process.scale_max = 1.4
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.35))
	curve.add_point(Vector2(0.35, 1.0))
	curve.add_point(Vector2(1.0, 1.6))
	var scale_curve := CurveTexture.new()
	scale_curve.curve = curve
	process.scale_curve = scale_curve
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.0))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	fade.add_point(0.15, Color(1, 1, 1, 0.85))
	fade.add_point(0.6, Color(1, 1, 1, 0.35))
	var fade_texture := GradientTexture1D.new()
	fade_texture.gradient = fade
	process.color_ramp = fade_texture
	_particles.process_material = process
	# one billboard quad, drawn soft and unlit: the colour comes from the material, not from a texture
	var quad := QuadMesh.new()
	quad.size = Vector2(0.16, 0.16)
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_material.vertex_color_use_as_albedo = true
	_material.albedo_color = VAPOUR_COLOUR
	quad.material = _material
	_particles.draw_pass_1 = quad
	add_child(_particles)


# The plume leaves the outlet along the gas, just outside the pipe.
func place(at: Vector3, out_dir: Vector3) -> void:
	var dir := out_dir.normalized() if out_dir.length() > 0.001 else Vector3.FORWARD
	if not is_inside_tree():
		position = at + dir * 0.02
		return
	global_position = at + dir * 0.02
	if dir.cross(Vector3.UP).length() > 0.001:
		look_at(global_position + dir, Vector3.UP)


# gas_temp_k: the exhaust gas temperature. mass_flow: kg/s leaving the cylinders. lambda: the mixture the engine is running.
# delta: seconds since the last call, for the soot's build-up and clear-down.
func update(gas_temp_k: float, mass_flow: float, lambda: float, delta: float) -> void:
	_flow_share = clampf(mass_flow / FLOW_REFERENCE, 0.0, 1.0)
	var flowing := mass_flow > MIN_FLOW
	# vapour: full at or below VAPOUR_FULL_K, gone at VAPOUR_TOP_K
	_vapour = clampf((VAPOUR_TOP_K - gas_temp_k) / (VAPOUR_TOP_K - VAPOUR_FULL_K), 0.0, 1.0) if flowing else 0.0
	# soot: builds while the mixture is rich, clears when it is not
	var rich := (lambda < SOOT_LAMBDA) and flowing
	var tau := SOOT_BUILD_TAU if rich else SOOT_CLEAR_TAU
	var target := 1.0 if rich else 0.0
	_soot += (target - _soot) * minf(maxf(delta, 0.0) / tau, 1.0)
	_density = clampf(_flow_share * maxf(_vapour, _soot), 0.0, 1.0)
	_apply()


func _apply() -> void:
	if _particles == null:
		return
	_particles.emitting = _density > 0.01
	_particles.amount_ratio = clampf(_density, 0.02, 1.0)
	if _material != null:
		# a rich pipe smokes dark, and the two mix while the soot is building
		var soot_share := 0.0 if (_vapour + _soot) <= 0.0 else _soot / (_vapour + _soot)
		_material.albedo_color = VAPOUR_COLOUR.lerp(SOOT_COLOUR, soot_share)


# What is being drawn, for the tests and the stats readout: 0..1 of the particle pool, and the two shares that decide its colour.
func density() -> float:
	return _density


func vapour() -> float:
	return _vapour


func soot() -> float:
	return _soot


func emitting_now() -> bool:
	return _particles != null and _particles.emitting
