class_name Crankshaft
extends Node3D

# The one-piece crankshaft, drawn from EngineSpec's own numbers and from the parts a crank actually has:
#   nose pulley -> main journal -> counterweight / crank pin / counterweight -> main journal -> ... -> flywheel
#   flange -> flywheel.
# Nothing here invents a size: the main journals are the spec's Ø28 mm, the crank pins its Ø27 mm, the counterweight
# lobe is the spec's bore-proportional sector opposite the pin, and the flywheel keeps the spec's mass and radius.
# EngineSpec.crank_mass_kg() and crank_inertia() add up the same parts, so the picture and the physics agree.
#
# The crank turns about +x (the crank axis). Each crank pin is its own node, so a rod can follow it; the counterweights
# are extruded lobes (CSGPolygon3D in MODE_DEPTH), not discs, because that is the shape that gives a crank its balance.

const M := Units.M_TO_SCENE
const OUTLINE_SEGMENTS := 24 # points on each arc of a counterweight lobe
const BAY_FILL := 0.72 # at most this share of the station pitch, so the webs of neighbouring pins never meet
const MIN_JOURNAL_WIDTH := 0.012 # m, the narrowest journal the drawing will show

var _spec: EngineSpec
var throws: Array[Node3D] = [] # one per crank pin, rotating about x at its own phase
var journals: Array[MeshInstance3D] = [] # main journals, the surfaces that run in the crankcase
var crank_pins: Array[MeshInstance3D] = []
var counterweights: Array[CSGPolygon3D] = []
var pulley: MeshInstance3D # accessory pulley on the nose
var pulley_flange: MeshInstance3D # the lip that keeps the belt on the pulley
var flywheel_flange: MeshInstance3D # the crank flange the flywheel bolts to
var flywheel: Node3D # the flywheel, a disc of the spec's mass and radius
var body_half := 0.0 # scene units, half the crank's overall length along x
var throw_radius := 0.0 # scene units, the crank radius (half the stroke)


# pin_layout: one entry per crank pin, {"deg": pin angle in degrees, "x": station centre along the crank}.
# pitch: station spacing, scene units. body_half: half the crank's overall length, so the nose and flange ends stay
# where the rest of the engine expects them (the primary gear and clutch line up on the left stub, the flywheel right).
func build(spec: EngineSpec, pin_layout: Array, pitch: float, half_length: float) -> void:
	_spec = spec
	body_half = half_length
	throw_radius = spec.crank_throw_m() * M
	var pin_r := EngineSpec.CRANK_PIN_RADIUS * M
	var pin_w := EngineSpec.CRANK_PIN_WIDTH * M
	var mj_r := EngineSpec.MAIN_JOURNAL_RADIUS * M
	var mj_w := maxf(spec.main_journal_width_m() * M, MIN_JOURNAL_WIDTH * M)
	var arm_r := spec.web_arm_radius_m() * M # the web reaches past the pin on the pin side
	var cw_r := spec.counterweight_radius_m() * M # and carries the balance mass on the far side
	var pulley_r := EngineSpec.PULLEY_RADIUS * M
	var pulley_w := EngineSpec.PULLEY_WIDTH * M
	var flange_r := EngineSpec.FLYWHEEL_FLANGE_RADIUS * M
	var flange_w := EngineSpec.FLYWHEEL_FLANGE_WIDTH * M
	var web_t := spec.counterweight_thickness_m() * M
	# never let a web run into the pin bay of the next station
	var bay := minf(pin_w + 2.0 * web_t, pitch * BAY_FILL)
	web_t = (bay - pin_w) * 0.5
	if web_t <= 0.0:
		web_t = pitch * 0.12
		bay = pin_w + 2.0 * web_t

	# stations: the unique axial positions a pin sits at, smallest first
	var stations: Array[float] = []
	for pin in pin_layout:
		var x: float = pin["x"]
		if not stations.has(x):
			stations.append(x)
	stations.sort()

	var steel := _mat(Color(0.52, 0.53, 0.56), 0.34)
	if stations.is_empty():
		# no pins: a bare shaft, so a spec under construction still draws something
		_add_cyl(self, mj_r, body_half * 2.0, Vector3.ZERO, steel).name = "MainJournal0"
		return

	var left := stations[0] - bay * 0.5
	var right := stations[stations.size() - 1] + bay * 0.5
	# the journals that run in the cases: one either side of the bays and one between every pair of stations
	var edges: Array[float] = []
	for i in stations.size() - 1:
		edges.append((stations[i] + stations[i + 1]) * 0.5)
	# the nose stub carries the pulley and the flywheel end carries the flange, so the journals stop at their faces
	_add_journal(-body_half + pulley_w, left, mj_r, steel)
	var gap := maxf(pitch - bay, mj_w) # the journal fills the space the counterweights leave between two bays
	for edge in edges:
		_add_journal(edge - gap * 0.5, edge + gap * 0.5, mj_r, steel)
	_add_journal(right, body_half - flange_w, mj_r, steel)

	# one throw per pin: the pin at its angle, with a counterweight either side, opposite the pin
	for i in pin_layout.size():
		var pin: Dictionary = pin_layout[i]
		var throw := Node3D.new()
		throw.name = "CrankThrow%d" % i
		throw.position = Vector3(pin["x"], 0.0, 0.0)
		throw.rotation.x = deg_to_rad(pin["deg"])
		add_child(throw)
		throws.append(throw)
		var journal := _add_cyl(throw, pin_r, pin_w, Vector3(0.0, throw_radius, 0.0), steel)
		journal.name = "CrankPin%d" % i
		crank_pins.append(journal)
		for side in [-1.0, 1.0]:
			var x: float = side * (pin_w + web_t) * 0.5
			var lobe := _add_counterweight(throw, arm_r, cw_r, web_t, x, steel)
			lobe.name = "Counterweight%d%s" % [i, "L" if side < 0.0 else "R"]
			counterweights.append(lobe)

	# the nose: a pulley on the very end of the crank, outboard of the front journal, with a lip on its outer face
	pulley = _add_cyl(self, pulley_r, pulley_w, Vector3(-body_half + pulley_w * 0.5, 0.0, 0.0), steel)
	pulley.name = "Pulley"
	pulley_flange = _add_cyl(self, pulley_r * 1.12, pulley_w * 0.16,
		Vector3(-body_half + pulley_w * 0.58, 0.0, 0.0), steel)
	pulley_flange.name = "PulleyFlange"

	# the flywheel end: a flange on the crank, then the flywheel bolted to its face
	flywheel_flange = _add_cyl(self, flange_r, flange_w, Vector3(body_half - flange_w * 0.5, 0.0, 0.0), steel)
	flywheel_flange.name = "FlywheelFlange"
	# six flange bolts, on the bolt circle between the shaft and the flange rim
	var bolt := _mat(Color(0.72, 0.72, 0.75), 0.3)
	for k in 6:
		var a := TAU * k / 6.0
		var at := Vector3(body_half - flange_w, flange_r * 0.62 * cos(a), flange_r * 0.62 * sin(a))
		_add_cyl(self, flange_r * 0.09, flange_w * 1.4, at, bolt).name = "FlangeBolt%d" % k

	var fw_r := spec.flywheel_radius_m() * M
	var fw_t := spec.flywheel_kg / (EngineSpec.STEEL_DENSITY * PI * spec.flywheel_radius_m() * spec.flywheel_radius_m()) * M
	flywheel = Node3D.new()
	flywheel.name = "Flywheel"
	flywheel.position = Vector3(body_half + fw_t * 0.5, 0.0, 0.0)
	add_child(flywheel)
	var disc := _add_cyl(flywheel, fw_r, fw_t, Vector3.ZERO, _mat(Color(0.28, 0.28, 0.3), 0.48))
	disc.name = "FlywheelDisc"
	# a lightening ring and a timing mark, both visible as the crank turns
	_add_cyl(flywheel, fw_r * 0.72, fw_t * 1.02, Vector3.ZERO, _mat(Color(0.2, 0.2, 0.22), 0.5)).name = "FlywheelWeb"
	_add_box(flywheel, Vector3(fw_t * 1.02, fw_r * 0.22, fw_r * 0.06),
		Vector3(0.0, fw_r * 0.8, 0.0), _mat(Color(0.9, 0.9, 0.9), 0.5)).name = "TimingMark"


# Pin angle of throw i, degrees: what a rod or a crank sensor reads.
func pin_angle(i: int) -> float:
	return rad_to_deg(throws[i].rotation.x)


# One main journal between two x positions, as a cylinder about the crank axis.
func _add_journal(from_x: float, to_x: float, radius: float, mat: Material) -> void:
	var width := to_x - from_x
	if width <= 0.0005:
		return
	var journal := _add_cyl(self, radius, width, Vector3((from_x + to_x) * 0.5, 0.0, 0.0), mat)
	journal.name = "MainJournal%d" % journals.size()
	journals.append(journal)


# One counterweight: the sector opposite the pin plus its hub, extruded along x by its thickness.
func _add_counterweight(parent: Node3D, arm_radius: float, mass_radius: float, thickness: float, x: float, mat: Material) -> CSGPolygon3D:
	var lobe := CSGPolygon3D.new()
	lobe.polygon = counterweight_outline(arm_radius, mass_radius, EngineSpec.COUNTERWEIGHT_ARM_DEG,
		EngineSpec.COUNTERWEIGHT_SPAN_DEG)
	lobe.mode = CSGPolygon3D.MODE_DEPTH
	lobe.depth = thickness
	lobe.material = mat
	lobe.rotation.y = PI / 2.0 # extrude along x
	lobe.position = Vector3(x, 0.0, 0.0) # CSGPolygon3D extrudes symmetrically about its own plane
	parent.add_child(lobe)
	return lobe


# Outline of one web, in the y-z plane, with the pin toward +y: the arm that reaches past the pin, then the balance
# mass on the far side. Solid plate, so the outline is a single closed curve and the journal passes through it.
static func counterweight_outline(arm_radius: float, mass_radius: float, arm_deg: float, span_deg: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var arm := deg_to_rad(arm_deg)
	var seg := OUTLINE_SEGMENTS
	# pin side, from -arm/2 to +arm/2 about +y
	for k in seg + 1:
		var t := -arm * 0.5 + arm * k / seg
		pts.append(Vector2(arm_radius * sin(t), arm_radius * cos(t)))
	# balance side, from +arm/2 the rest of the way round to -arm/2
	var sweep := TAU - arm
	for k in seg * 2 + 1:
		var t := arm * 0.5 + sweep * k / (seg * 2.0)
		pts.append(Vector2(mass_radius * sin(t), mass_radius * cos(t)))
	return pts


static func _add_cyl(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 28
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation.z = PI / 2.0 # cylinder axis along x
	parent.add_child(mi)
	return mi


static func _add_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _mat(c: Color, rough: float, alpha := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c, alpha)
	m.roughness = rough
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m
