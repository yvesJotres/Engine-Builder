extends Node3D

# A floor-standing sound level meter: a tripod on the ground, a mast, a head with a display, and a measurement capsule
# on a short boom aimed at the tailpipe. The capsule is this node's origin, so wherever the rig is placed is exactly
# where the reading is taken - that is the point of drawing it at all, since the microphone position moves whenever the
# exhaust layout is rebuilt.
#
# Sizes are scene units (1 unit = 10 cm), picked to a workshop instrument: 35 cm tripod footprint, 5 cm mast tube, a
# 25 cm boom to the capsule. The whole rig is 20-odd primitives and one Label3D, so it stays cheap on a phone.
#
# Usage:
#   var rig = SPL_RIG_SCRIPT.new(); rig.build(); add_child(rig)
#   rig.place(mic_world_position, tail_tip, Ground.Y); rig.set_reading("91 dB")
# place() only moves transforms and rescales the mast, so it is safe to call every frame.

const TRIPOD_RADIUS := 3.5 # units from the mast foot to each foot
const HUB_HEIGHT := 1.7 # units, the tallest the legs meet the mast above the ground
const BOOM_LENGTH := 2.5 # units from the mast head back to the capsule
const MAST_RADIUS := 0.22 # units, tube radius
const HEAD_SIZE := Vector3(1.5, 1.1, 1.2) # units, the instrument head
const CAPSULE_RADIUS := 0.55 # units, the grille
const DISPLAY_PIXEL_SIZE := 0.006 # Label3D pixel size; 64 px font gives about 3.8 cm tall digits

# Matched to the dyno cell's palette: dark grey instruments, a brushed-steel capsule.
var _dark := StandardMaterial3D.new()
var _body := StandardMaterial3D.new()
var _chrome := StandardMaterial3D.new()

var _tripod: Node3D # legs and hub, moved to the mast foot each placement
var _mast: MeshInstance3D # a unit-tall tube, scaled to the height between hub and head
var _knob: MeshInstance3D # clamp knob at the foot of the mast
var _head: Node3D # instrument body, display and boom root
var _display: Label3D # the live reading
var _capsule: Node3D # the microphone: this node's origin when placed
var _h := 0.0 # units between the capsule and the ground in the last placement
var _text := "-- dB"


func build() -> void:
	_dark.albedo_color = Color(0.12, 0.12, 0.14)
	_dark.roughness = 0.6
	_body.albedo_color = Color(0.24, 0.25, 0.27)
	_body.metallic = 0.35
	_body.roughness = 0.45
	_chrome.albedo_color = Color(0.78, 0.8, 0.83)
	_chrome.metallic = 0.9
	_chrome.roughness = 0.18
	# the capsule is the node origin: the boom holds it out in front of the head, toward the bike (local +z)
	_capsule = Node3D.new()
	_capsule.name = "Capsule"
	add_child(_capsule)
	var grille := _cyl(_capsule, CAPSULE_RADIUS, CAPSULE_RADIUS, CAPSULE_RADIUS * 2.2, _chrome)
	grille.name = "CapsuleGrille"
	grille.rotation.x = PI / 2.0 # the capsule points down +z, at the pipe
	var neck := _cyl(_capsule, CAPSULE_RADIUS * 0.75, CAPSULE_RADIUS * 0.75, CAPSULE_RADIUS * 1.6, _body)
	neck.name = "CapsuleBody"
	neck.position = Vector3(0.0, 0.0, -CAPSULE_RADIUS * 1.6)
	neck.rotation.x = PI / 2.0

	_head = Node3D.new()
	_head.name = "Head"
	_head.position = Vector3(0.0, 0.0, -BOOM_LENGTH)
	add_child(_head)
	var body := _box(_head, HEAD_SIZE, Vector3.ZERO, _body)
	body.name = "HeadBody"
	var boom := _cyl(_head, 0.16, 0.16, BOOM_LENGTH, _chrome)
	boom.name = "Boom"
	boom.rotation.x = PI / 2.0
	boom.position = Vector3(0.0, 0.0, BOOM_LENGTH * 0.5)
	# the display bezel and the readout, just above the head so the mast never crosses it
	var bezel := _box(_head, Vector3(1.25, 0.62, 0.14), Vector3(0.0, 0.42, 0.05), _dark)
	bezel.name = "DisplayBezel"
	_display = Label3D.new()
	_display.name = "Reading"
	_display.text = _text
	_display.font_size = 64
	_display.pixel_size = DISPLAY_PIXEL_SIZE
	_display.modulate = Color(0.45, 1.0, 0.55)
	_display.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
	_display.outline_size = 12
	_display.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_display.no_depth_test = false
	_display.position = Vector3(0.0, 0.42, 0.14)
	_head.add_child(_display)

	# the mast: a unit-tall tube from the hub up to the head, scaled per placement, plus a clamp knob
	_mast = _cyl(self, MAST_RADIUS, MAST_RADIUS, 1.0, _chrome)
	_mast.name = "Mast"
	_knob = _cyl(self, MAST_RADIUS * 2.6, MAST_RADIUS * 2.6, 0.5, _dark)
	_knob.name = "ClampKnob"
	_knob.position = Vector3(MAST_RADIUS * 1.8, 0.0, 0.0)
	_knob.rotation.z = PI / 2.0

	# the tripod: three legs from a hub down to the ground, splayed evenly
	_tripod = Node3D.new()
	_tripod.name = "Tripod"
	add_child(_tripod)
	var hub := _cyl(_tripod, MAST_RADIUS * 2.2, MAST_RADIUS * 2.2, MAST_RADIUS * 3.0, _body)
	hub.name = "Hub"
	for leg in 3:
		var angle := TAU * leg / 3.0
		# the legs are built one unit tall and the whole tripod is scaled to the height available on placement
		var foot := Vector3(sin(angle) * TRIPOD_RADIUS, -1.0, cos(angle) * TRIPOD_RADIUS)
		var from := Vector3(sin(angle) * MAST_RADIUS * 2.0, 0.0, cos(angle) * MAST_RADIUS * 2.0)
		var leg_mesh := _cyl(_tripod, 0.14, 0.14, from.distance_to(foot), _dark)
		leg_mesh.name = "Leg%d" % leg
		leg_mesh.transform = Transform3D(_basis_along(from - foot), (from + foot) * 0.5)
		# the pad's own height scales with the tripod, so lifting it by half its unit height keeps its underside on the
		# floor at any scale
		var pad := _cyl(_tripod, 0.3, 0.3, 0.22, _dark)
		pad.name = "Foot%d" % leg
		pad.position = foot + Vector3(0.0, 0.11, 0.0)
	set_reading(_text)


# Puts the capsule exactly at `at`, feet on `ground_y`, boom aimed at `aim_at`. Only transforms change here.
func place(at: Vector3, aim_at: Vector3, ground_y: float) -> void:
	global_position = at
	var look := aim_at - at
	look.y = 0.0 # the mast stays plumb; only the boom's heading follows the pipe
	if look.length_squared() < 1e-8:
		look = Vector3.BACK
	rotation = Vector3(0.0, atan2(look.x, look.z), 0.0)
	_h = at.y - ground_y
	# the legs are one unit tall in the mesh, scaled here to the height the head leaves them, so the feet land on the
	# floor whatever the pipe height is; the mast then spans whatever is left between the hub and the head
	var hub_drop := clampf(_h, 0.3, HUB_HEIGHT) # legs never taller than the instrument, never through the floor
	var hub_y := -_h + hub_drop
	_tripod.position = Vector3(0.0, hub_y, -BOOM_LENGTH)
	_tripod.scale = Vector3(1.0, hub_drop, 1.0)
	var mast_len := maxf(-hub_y, 0.05)
	_mast.scale = Vector3(1.0, mast_len, 1.0)
	_mast.position = Vector3(0.0, hub_y + mast_len * 0.5, -BOOM_LENGTH)
	_knob.position.y = hub_y + 0.35


func set_reading(text: String) -> void:
	_text = text
	if _display != null:
		_display.text = text


# Where the microphone is, in world space: the point the reading describes.
func capsule_position() -> Vector3:
	return global_position


# The lowest point of the feet, world space, so a test can check the rig stands on the floor.
func feet_y() -> float:
	var lowest := INF
	for child in _tripod.get_children():
		var pad := child as MeshInstance3D
		if pad == null or not pad.name.begins_with("Foot"):
			continue
		var box: AABB = pad.global_transform * pad.mesh.get_aabb()
		lowest = minf(lowest, box.position.y)
	return lowest


# Height of the capsule over the floor in the last placement, scene units (1 unit = 10 cm).
func mast_height() -> float:
	return _h


func display_text() -> String:
	return _display.text if _display != null else _text


# A basis whose +y runs along `dir`, for pointing a cylinder down a leg.
static func _basis_along(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var helper := Vector3.UP if absf(y.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	var x := y.cross(helper).normalized()
	var z := x.cross(y)
	return Basis(x, y, z)


func _cyl(parent: Node3D, top: float, bottom: float, height: float, mat: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 12
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi
