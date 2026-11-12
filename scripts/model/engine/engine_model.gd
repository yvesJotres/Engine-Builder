class_name EngineModel
extends Node3D

# The engine drawn from the simulation's own numbers, and only the parts the simulation uses: crankshaft (webs, pin, shaft),
# flywheel, balancer, and per cylinder a barrel, head, plug, four valves with their two camshafts, piston, rod, exhaust port, intake runner, throttle body and injector.
# Sizes come from EngineSpec, Cylinder, EngineAir and FuelTank, so a bigger bore, a longer stroke or a different compression
# ratio changes what is drawn. Everything else (cases, fins, covers) is left out because nothing in the simulation depends on it.
# Single-cylinder engines are just one unit. V layouts are drawn from their bank and fire angles, as engine-sim's panigale_v4.mr places them.

const MM := Units.MM_TO_SCENE
const PITCH_FACTOR := EngineSpec.CYLINDER_PITCH_FACTOR # cylinder centre spacing, in bores
const ENGINE_LOW := 0.75 # scene units, how far the lowest engine part hangs below the crank (the balancer weight)
const PISTON_CROWN := 0.30 # crown height above the piston pin, in bores, estimate
const PISTON_SKIRT := 0.32 # skirt depth below the pin, in bores, estimate
const HEAD_HEIGHT := 0.45 # in bores, estimate
const HEAD_RADIUS := 0.62 # in bores, estimate
const BARREL_WALL := 0.06 # scene units, 6 mm
const STEEL_DENSITY := 7800.0 # kg/m³
const STUB := 0.45 # scene units, crank shaft past the outer cylinder's throw on each side, holds the flywheel and the primary gear
const CAM_BASE := 0.12 # scene units, cam base circle radius, 12 mm, estimate
const LOBE_WIDTH := 0.08 # scene units, estimate
# Combustion, drawn from the simulation's own burn state: the charge lights at the plug, the flame front fills the
# chamber as burn_energy_left falls, and the colour follows the gas temperature. The flame is a glow, not a combustion
# model - its SIZE is chosen to read on a 5 cm bore, its TIMING and heat are the simulation's. The spark is a flash plus
# a light, so it still shows with the covers on: the covers hide the flame, they cannot hide the light through them.
const FLAME_COOL_K := 1500.0 # K, a rich flame just after the spark: deep orange
const FLAME_HOT_K := 2500.0 # K, a fully burned charge at its peak: yellow-white
const FLAME_MIN_SCALE := 0.18 # bore radii: the kernel at the plug
const FLAME_MAX_SCALE := 0.49 # bore radii: the front reaching the barrel wall, never through it
const FLAME_FADE := 0.05 # s the glow takes to die once the burn is over
const SPARK_FLASH_TIME := 0.06 # s, long enough to read at 60 fps instead of flickering on a frame boundary
const SPARK_LIGHT_ENERGY := 4.0 # the flash's light, bright enough to light the head from inside

var _pistons: Array[Node3D] = []
var _rods: Array[Node3D] = [] # rod groups, one per cylinder
var _rod_shafts: Array[MeshInstance3D] = []
var _rod_smalls: Array[MeshInstance3D] = []
var _rod_bigs: Array[MeshInstance3D] = []
var _pin_x: Array[float] = [] # cylinder position along the crank, scene units
var _pin_phase: Array[float] = [] # crank-pin angle per cylinder, degrees
var _plates: Array[MeshInstance3D] = [] # butterfly plate per throttle body
var _ports: Array[Vector3] = [] # exhaust port per cylinder, model space
var _cams: Array[Dictionary] = [] # each: node, intake flag, cylinder index
var _spec: EngineSpec # the spec the drawing was built from: its cam timing and lift drive the valves
var _valves: Array[Dictionary] = [] # each: node, seat height, intake flag, cylinder index; intake first within a cylinder
var _banks: Array[Node3D] = [] # one per cylinder: the bank's own turned frame, so a test can ask which way it faces
var _throttle_bodies: Array[Node3D] = [] # one per cylinder: the drawn throttle body, carrying its length and bore
var _high_points: Array[Vector3] = [] # highest parts (plugs, throttle bodies), model space, so the tank can sit above them
var _injector_local := Vector3.ZERO # nozzle on the first throttle body, model space
var _throttle_local := Vector3.ZERO # centre of the first throttle body, model space
var _intake_mouths: Array[Vector3] = [] # where each cylinder breathes in, model space: a velocity stack or a carburettor mouth
var _airbox_gap := 0.0 # scene units between the mouths and the airbox front wall: the rubber boot on a carburettor
var _airbox_dir := Vector3(0.0, 0.0, -1.0) # the way the airbox lies from its mouths, model space
var _injector_points: Array[Vector3] = [] # every nozzle, model space: one per cylinder with an injector or a carburettor jet
var _carb_feed_points: Array[Vector3] = [] # external fuel inlets on carburettor float bowls
var _stroke := 0.0
var _rod_len := 0.0
var _crank_node: Node3D
var _crank_y := 0.0 # crank centre height, set so the piston pin bottoms out at y = 0
var _balancer: Node3D # counter-balancer shaft, turns opposite the crank
var _flywheel: Node3D
var _span := 0.0 # distance between the outer cylinder centres
var _shaft_len := 0.0 # crank shaft between the stubs
var _assembled := false
var _covers: Array[Node3D] = []
var _inspection_shells: Array[Node3D] = []
var _two_stroke_exterior: Array[MeshInstance3D] = []
var _chambers: Array[Dictionary] = [] # per cylinder: the bank frame, the plug point and the bore, for the flame and spark
var _flames: Array[MeshInstance3D] = []
var _sparks: Array[MeshInstance3D] = []
var _spark_lights: Array[OmniLight3D] = []
var _spark_left: Array[float] = [] # s the spark still shows for
var _burn_seen: Array[float] = [] # burn fraction last frame, so this frame's ignition can be found
var _flame_level: Array[float] = [] # 0..1 brightness, held for FLAME_FADE after the burn ends
var _flame_front: Array[float] = [] # 0..1 of the way from the plug to the wall: the flame front's radius


# Height of the crank above the ground: the exhaust runs under the engine at the ground clearance, so the engine sits on it.
static func crank_world_y() -> float:
	return Ground.Y + ExhaustLayout.GROUND_CLEARANCE + ExhaustLayout.CAT_R + ExhaustLayout.COLLECTOR_R + ENGINE_LOW + 0.05


func build(spec: EngineSpec) -> void:
	_spec = spec
	_build_engine(spec)
	# lean the whole engine about the crankshaft, which sits at its real height above the ground
	var rot := Basis(Vector3.RIGHT, deg_to_rad(spec.slant_deg))
	var c := _crank_node.position if _crank_node != null else Vector3.ZERO
	transform = Transform3D(rot, Vector3(0.0, crank_world_y(), 0.0) - rot * c)


# Where the primary drive gear sits along the crank, on the left stub (the flywheel is on the right), so the gearbox and clutch can line up.
func primary_gear_x() -> float:
	return -(_shaft_len * 0.5 + 0.2)


func _build_engine(spec: EngineSpec) -> void:
	for c in get_children():
		c.queue_free()
	_pistons.clear()
	_rods.clear()
	_rod_shafts.clear()
	_rod_smalls.clear()
	_rod_bigs.clear()
	_pin_x.clear()
	_pin_phase.clear()
	_plates.clear()
	_ports.clear()
	_valves.clear()
	_cams.clear()
	_high_points.clear()
	_injector_points.clear()
	_carb_feed_points.clear()
	_intake_mouths.clear()
	_banks.clear()
	_throttle_bodies.clear()
	_covers.clear()
	_inspection_shells.clear()
	_two_stroke_exterior.clear()
	_chambers.clear()
	_flames.clear()
	_sparks.clear()
	_spark_lights.clear()
	_spark_left.clear()
	_burn_seen.clear()
	_flame_level.clear()
	_flame_front.clear()
	_airbox_gap = 0.0

	var n := spec.cylinders
	var bore := spec.bore_mm * MM
	var s := spec.stroke_mm * MM
	var r := s * 0.5
	var L := s * spec.rod_ratio
	_stroke = s
	_rod_len = L
	_crank_y = r - L
	var pitch := bore * PITCH_FACTOR
	_span = (n - 1) * pitch
	var fire := FiringOrders.for_spec(spec)
	# Each cylinder's bank angle and its crank-pin angle. As engine-sim's panigale_v4.mr places them, wires 1 and 3 (cylinders 1 and 3)
	# are on the -45 degree bank and wires 2 and 4 on the +45 degree bank. A pin angle is bank angle + fire angle, so the
	# cylinders on one pin share it: a V takes two pins, 120 degrees apart, as the wiring implies.
	var alpha: Array[float] = []
	var pin_deg: Array[float] = []
	var is_v := spec.layout == "V"
	var is_w := spec.layout == "W"
	var shared_pairs := is_v and spec.shared_v_crankpins
	for i in n:
		var a := (spec.bank_angle * 0.5 if i % 2 == 1 else -spec.bank_angle * 0.5) if is_v else 0.0
		if spec.v3r_style and is_v and n == 3:
			a = -a # two cylinders lean towards the front of the motorcycle
		if is_w:
			var outer := spec.bank_angle * 0.5
			var inner := 7.5
			a = [-outer - inner, -outer + inner, outer - inner, outer + inner][i % 4]
		alpha.append(a)
		pin_deg.append(fposmod(a + fire[i], 360.0))
	# pins: one per unique pin angle (V), so cylinders that share a pin share its x position; one per cylinder inline
	var pins: Array[float] = []
	var pin_of: Array[int] = []
	for i in n:
		if is_w:
			pins.append(pin_deg[i])
			pin_of.append(int(i / 4.0))
			continue
		if shared_pairs:
			if i % 2 == 0:
				pins.append(pin_deg[i])
			pin_of.append(int(i / 2.0))
			continue
		if is_v:
			# A dual-pin V gives every cylinder its own journal, even when two of them sit at the same angle (0 or
			# 360 degrees of separation). Merging them by angle drew a single-pin crank while the firing was dual-pin.
			pins.append(pin_deg[i])
			pin_of.append(pins.size() - 1)
			continue
		# inline: one pin per cylinder
		pins.append(pin_deg[i])
		pin_of.append(pins.size() - 1)
	var stations := ceili(n / 4.0) if is_w else pins.size()
	_span = (stations - 1) * pitch
	_shaft_len = _span + EngineSpec.SHAFT_LENGTH * Units.M_TO_SCENE

	var steel := _mat(Color(0.45, 0.45, 0.48), 0.4)
	var iron := _mat(Color(0.2, 0.2, 0.22), 0.5)
	var alu := _mat(Color(0.6, 0.6, 0.63), 0.35)
	# Estimated exterior casing, kept separate from the moving crank for cutaway view.
	var case := _add_box(self, Vector3(_shaft_len + bore * 0.5, bore * 1.05, bore * 1.15), Vector3(0, _crank_y, 0), iron)
	case.name = "CrankcaseCover"
	_covers.append(case)
	# Casting seam and bolt heads are visual estimates, not measured hardware.
	var fastener := _mat(Color(0.7, 0.7, 0.72), 0.38)
	for side in [-1.0, 1.0]:
		for end in [-1.0, 1.0]:
			var bolt := _add_cyl(case, bore * 0.035, bore * 0.025, Vector3(end * (_shaft_len * 0.5), side * bore * 0.36, bore * 0.58), fastener)
			bolt.rotation.x = PI / 2.0

	# crank: nose pulley, main journals, counterweights, crank pins and the flywheel flange, built by Crankshaft from
	# EngineSpec's own sizes, so the drawing and crank_mass_kg()/crank_inertia() describe the same hardware
	var m := Units.M_TO_SCENE
	var crank_layout: Array = []
	for k in pins.size():
		var x := -(stations - 1) * pitch * 0.5 + (pin_of[k] if is_w else k) * pitch
		crank_layout.append({"deg": pins[k], "x": x})
	var crank := Crankshaft.new()
	crank.build(spec, crank_layout, pitch, _shaft_len * 0.5 + STUB)
	_crank_node = crank
	_crank_node.position = Vector3(0, _crank_y, 0)
	add_child(_crank_node)
	_flywheel = crank.flywheel

	for i in n:
		var x := -(stations - 1) * pitch * 0.5 + pin_of[i] * pitch
		if shared_pairs and (i % 2 == 1 or i + 1 < n):
			x += (-1.0 if i % 2 == 0 else 1.0) * bore * 0.075
		_pin_x.append(x)
		_pin_phase.append(-fire[i]) # crank - fire, as the simulator's cylinder phase

	# balancer shaft below and ahead of the crank, its weight of balancer_kg at BALANCER_RADIUS, turning opposite the crank
	_balancer = Node3D.new()
	_balancer.position = Vector3(0.0, _crank_y - 0.5, 0.35)
	add_child(_balancer)
	var bal_r := 0.12
	var bal_len := spec.balancer_kg / STEEL_DENSITY / (PI * pow(bal_r / m, 2.0)) * m
	var bal_shaft := _add_cyl(_balancer, 0.08, _shaft_len, Vector3.ZERO, steel)
	bal_shaft.rotation.z = PI / 2.0
	var bal_weight := _add_cyl(_balancer, bal_r, bal_len, Vector3(0.0, -EngineSpec.BALANCER_RADIUS * m, 0.0), iron)
	bal_weight.rotation.z = PI / 2.0

	# each cylinder sits in its own bank, turned by its bank angle about the crank centre; inline banks are not turned
	var centre := Vector3(0.0, _crank_y, 0.0)
	for i in n:
		var rot := Basis(Vector3.RIGHT, deg_to_rad(alpha[i]))
		var xf := Transform3D(rot, centre - rot * centre)
		var bank := Node3D.new()
		bank.transform = xf
		bank.name = "Bank%d" % i
		add_child(bank)
		_banks.append(bank)
		# a bank's exhaust leaves on its outside and its intake faces the valley, so the sign of the lean picks the side;
		# an upright cylinder has no valley, and keeps the exhaust at the front
		var outboard := -1.0 if alpha[i] < 0.0 else 1.0
		_build_cylinder(spec, _pin_x[i], bore, s, alu, steel, i, bank, xf, outboard)
	if spec.induction == "injection" and _injector_points.size() > 1:
		IntakeModel.build_fuel_rail(self, steel)
	# fuel-injected four-strokes breathe straight from their velocity stacks for now; only carburettors get the airbox
	if spec.induction == "carburettor" and not _intake_mouths.is_empty():
		IntakeModel.build_airbox(self, spec, steel)
	set_assembled_view(_assembled)


func set_assembled_view(assembled: bool) -> void:
	_assembled = assembled
	for cover in _covers:
		cover.visible = assembled
	for shell in _inspection_shells:
		shell.visible = not assembled


# One cylinder: barrel, head with its plug, piston, rod, exhaust port, and the intake runner to a throttle body with its injector.
func _build_cylinder(spec: EngineSpec, x: float, bore: float, s: float, alu: Material, steel: Material, index: int, bank: Node3D, xf: Transform3D, outboard := 1.0) -> void:
	if spec.stroke_type == "two_stroke":
		_build_two_stroke_cylinder(spec, x, bore, s, alu, steel, index, bank, xf)
		return
	var barrel_mat := _mat(Color(0.6, 0.6, 0.63), 0.35, 0.35)
	var black := _mat(Color(0.05, 0.05, 0.05), 0.6)
	var bottom := -(PISTON_SKIRT + 0.03) * bore # barrel bottom, below the skirt at the bottom of the stroke
	# the deck sits where the piston crown reaches at the top, plus the clearance height that gives the compression ratio
	var deck := s + PISTON_CROWN * bore + s / (spec.compression_ratio - 1.0)
	var head_h := HEAD_HEIGHT * bore

	var barrel_pos := Vector3(x, (deck + bottom) * 0.5, 0)
	var head_pos := Vector3(x, deck + head_h * 0.5, 0)
	_inspection_shells.append(_add_cyl(bank, bore * 0.5 + BARREL_WALL, deck - bottom, barrel_pos, barrel_mat))
	_inspection_shells.append(_add_cyl(bank, bore * HEAD_RADIUS, head_h, head_pos, barrel_mat))
	var exterior := _mat(Color(0.48, 0.5, 0.53), 0.48)
	var barrel_cover := _add_cyl(bank, bore * 0.5 + BARREL_WALL, deck - bottom, barrel_pos, exterior)
	barrel_cover.name = "CylinderCover%d" % index
	_covers.append(barrel_cover)
	var head_cover := _add_cyl(bank, bore * HEAD_RADIUS, head_h, head_pos, exterior)
	head_cover.name = "HeadCover%d" % index
	_covers.append(head_cover)
	# Estimated rocker cover bridges the two camshafts on this cylinder.
	var rocker := _add_box(bank, Vector3(bore * 0.95, bore * 0.22, bore * 0.95), Vector3(x, deck + head_h * 1.15 + CAM_BASE, 0), iron_material())
	rocker.name = "RockerCover%d" % index
	_covers.append(rocker)
	_build_valves(x, bore, deck, head_h, bore * PITCH_FACTOR, index, steel, bank, outboard)
	var plug_top := deck + head_h + 0.5
	_add_cyl(bank, 0.07, 0.5, Vector3(x, deck + head_h + 0.25, 0), black)
	_high_points.append(xf * Vector3(x, plug_top, 0.0))
	# exhaust port on the outside of the head: the front on an upright cylinder, the outboard face of a V bank
	_ports.append(xf * Vector3(x, deck + head_h * 0.5, outboard * bore * HEAD_RADIUS))

	IntakeModel.build_runner(self, bank, x, bore, deck, head_h, index, xf, alu, steel, -outboard)

	_build_piston_rod(bank, bore, steel)
	_add_combustion(bank, x, bore, deck)


# Every nozzle, in world space: the fuel rail and the injector pulses use these.
func injector_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for p in _injector_points:
		out.append(transform * p)
	return out


func fuel_feed_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	if _spec.induction == "carburettor" and not _carb_feed_points.is_empty():
		for point in _carb_feed_points:
			out.append(transform * point)
		return out
	var rail_offset := Vector3(0, 0.12, 0) if _spec.induction == "injection" and _injector_points.size() > 1 else Vector3.ZERO
	for point in _injector_points:
		out.append(transform * (point + rail_offset))
	return out


# Piston and connecting rod, the same on both strokes: the piston follows the crank pin through _update_rod.
func _build_piston_rod(bank: Node3D, bore: float, steel: Material) -> void:
	# piston: a cylinder of the bore with its pin across it; the pin sits at the node origin, which the rod drives
	var piston := Node3D.new()
	bank.add_child(piston)
	var height := (PISTON_CROWN + PISTON_SKIRT) * bore
	var piston_radius := bore * 0.5 - 0.01
	_add_cyl(piston, piston_radius, height, Vector3(0, (PISTON_CROWN - PISTON_SKIRT) * 0.5 * bore, 0), _mat(Color(0.72, 0.74, 0.75), 0.3))
	var ring_material := _mat(Color(0.17, 0.19, 0.2), 0.45)
	for ring_index in 3:
		var ring := _add_cyl(piston, piston_radius + 0.002, bore * 0.025, Vector3(0, bore * (0.25 - ring_index * 0.055), 0), ring_material)
		ring.name = "PistonRing%d" % ring_index
	var gudgeon := _add_cyl(piston, bore * 0.12, bore * 0.8, Vector3.ZERO, steel)
	gudgeon.rotation.z = PI / 2.0
	_pistons.append(piston)

	# connecting rod: I-beam shaft (thin across the swing plane, wide along the crank axis), small and big end rings
	var rod := Node3D.new()
	bank.add_child(rod)
	_rods.append(rod)
	_rod_shafts.append(_add_box(rod, Vector3(bore * 0.1, _rod_len, bore * 0.2), Vector3.ZERO, steel))
	var small := _add_cyl(rod, bore * 0.12, bore * 0.12, Vector3.ZERO, steel)
	small.rotation.z = PI / 2.0
	_rod_smalls.append(small)
	var big := _add_cyl(rod, bore * 0.22, bore * 0.12, Vector3.ZERO, steel)
	big.rotation.z = PI / 2.0
	_rod_bigs.append(big)


# Two-stroke cylinder: barrel, head with its plug, transfer windows, exhaust port, reed block, piston and rod. No valves,
# cams or intake runner. The expansion chamber is drawn with the exhaust pipes (ExpansionChamber), from the same layout the solver uses.
func _build_two_stroke_cylinder(spec: EngineSpec, x: float, bore: float, s: float, alu: Material, steel: Material, index: int, bank: Node3D, xf: Transform3D) -> void:
	var barrel_mat := _mat(Color(0.6, 0.6, 0.63), 0.35, 0.35)
	var black := _mat(Color(0.05, 0.05, 0.05), 0.6)
	var bottom := -(PISTON_SKIRT + 0.03) * bore
	var deck := s + PISTON_CROWN * bore + s / (spec.compression_ratio - 1.0)
	var head_h := HEAD_HEIGHT * bore
	_two_stroke_exterior.append(_add_cyl(bank, bore * 0.5 + BARREL_WALL, deck - bottom, Vector3(x, (deck + bottom) * 0.5, 0), barrel_mat))
	_two_stroke_exterior.append(_add_cyl(bank, bore * HEAD_RADIUS, head_h, Vector3(x, deck + head_h * 0.5, 0), barrel_mat))
	var plug_top := deck + head_h + 0.5
	_add_cyl(bank, 0.07, 0.5, Vector3(x, deck + head_h + 0.25, 0), black)
	_high_points.append(xf * Vector3(x, plug_top, 0.0))
	# exhaust port on the front of the head: where the expansion chamber starts
	var exhaust := Vector3(x, deck + head_h * 0.5, bore * HEAD_RADIUS)
	_ports.append(xf * exhaust)
	# transfer windows, one either side of the barrel near the bottom of the stroke
	var window_y := bottom * 0.5
	for side in [-1.0, 1.0]:
		_add_box(bank, Vector3(0.02, bore * 0.25, bore * 0.5), Vector3(x + side * (bore * 0.5 + BARREL_WALL), window_y, 0.0), black)
	# reed block on the back of the crankcase, where the intake charge comes in
	IntakeModel.build_reed_block(self, bank, x, bore, bottom)
	if spec.induction == "carburettor":
		IntakeModel.build_carburettor(self, bank, x, bore, bottom, xf, index)
	_build_piston_rod(bank, bore, steel)
	_add_combustion(bank, x, bore, deck)


# Two intake valves toward the valley and two exhaust valves toward the outside of the bank, sized from the Cylinder
# constants (shrunk to fit a small bore), each pushed down by a cam lobe on a camshaft above it. The lobe outline is the
# Cylinder lift curve, so the cam and the valve agree; the camshaft turns once per two crank turns.
func _build_valves(x: float, bore: float, deck: float, head_h: float, pitch: float, index: int, mat: Material, bank: Node3D, outboard := 1.0) -> void:
	for intake in [true, false]:
		var d: float = minf(Cylinder.INTAKE_VALVE_D if intake else Cylinder.EXHAUST_VALVE_D, bore * 0.36 / Units.M_TO_SCENE) * Units.M_TO_SCENE
		var z := (-1.0 if intake else 1.0) * bore * 0.22 * outboard # intake inboard, exhaust outboard
		var cam := Node3D.new() # the camshaft's turn for this cylinder, axis along x above the valve stems
		cam.position = Vector3(x, deck + head_h * 1.1 + CAM_BASE, z)
		bank.add_child(cam)
		var shaft := _add_cyl(cam, 0.06, pitch * 0.95, Vector3.ZERO, mat)
		shaft.rotation.z = PI / 2.0
		_cams.append({"node": cam, "intake": intake, "cyl": index})
		for side in [-1, 1]:
			var valve := Node3D.new()
			valve.position = Vector3(x + side * d * 0.6, deck, z)
			bank.add_child(valve)
			_add_cyl(valve, d * 0.5, 0.02, Vector3(0.0, 0.01, 0.0), mat) # the face, seated at the deck when closed
			_add_cyl(valve, 0.025, head_h * 1.1, Vector3(0.0, head_h * 0.55, 0.0), mat) # the stem, up through the head
			_valves.append({"node": valve, "seat": deck, "intake": intake, "cyl": index})
			var lobe := CSGPolygon3D.new()
			lobe.polygon = _lobe_outline(intake, _spec)
			lobe.mode = CSGPolygon3D.MODE_DEPTH
			lobe.depth = LOBE_WIDTH
			lobe.material = mat
			lobe.rotation.y = PI / 2.0 # extrude along x
			lobe.position = Vector3(side * d * 0.6 - LOBE_WIDTH * 0.5, 0.0, 0.0)
			cam.add_child(lobe)


# Cam lobe outline: radius is the base circle plus the valve lift. A point at angle w from +y toward +z sits at world angle
# w + cam angle, and the stem is straight below (w = 180°), so w gives the cycle angle phi = 2 (180° - w) while the cam turns phi / 2.
static func _lobe_outline(intake: bool, spec: EngineSpec) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 120:
		var w := TAU * k / 120.0
		var phi := fposmod(2.0 * (180.0 - rad_to_deg(w)), 720.0)
		var lift := Cylinder.valve_lift(spec, intake, phi)
		var r := CAM_BASE + lift * Units.M_TO_SCENE
		pts.append(Vector2(-r * sin(w), r * cos(w)))
	return pts


# How far valve i (intake pair first, then exhaust pair, cylinder by cylinder) is open, scene units.
func valve_lift(i: int) -> float:
	return _valves[i].seat - _valves[i].node.position.y


# opening 0 = closed (plate lies across the flow), 1 = wide open (plate parallel to it).
func set_throttle(opening: float) -> void:
	for plate in _plates:
		plate.rotation.z = opening * PI / 2.0


# Injector nozzle in world space, so the fuel line can reach it.
func injector_position() -> Vector3:
	return transform * _injector_local


# Centre of the first throttle body in world space.
func throttle_position() -> Vector3:
	return transform * _throttle_local


# Height of the highest engine part in world space (a plug or a throttle body), for the tank to sit above.
func highest_y() -> float:
	var top := -INF
	for p in _high_points:
		top = maxf(top, (transform * p).y)
	# The runners can rise well above the throttle bodies, particularly on leaned
	# engines. Include their mouths and a radius allowance when placing the tank.
	var mouth_clearance := maxf(0.25, _spec.throttle_bore_mm * MM * 0.5 * IntakeModel.STACK_FLARE)
	for p in _intake_mouths:
		top = maxf(top, (transform * p).y + mouth_clearance)
	return top


# Bounding box of the engine's fixed exterior in the parent's coordinates. Excludes
# moving internals and intake/exhaust accessories; valid in either inspection view.
func chassis_envelope() -> AABB:
	var parts: Array[Node3D] = []
	parts.append_array(_covers)
	parts.append_array(_two_stroke_exterior)
	var bounds := AABB()
	var first := true
	for part in parts:
		if not part is MeshInstance3D:
			continue
		var xf := Transform3D.IDENTITY
		var node: Node3D = part
		while node != self:
			xf = node.transform * xf
			node = node.get_parent() as Node3D
		var box: AABB = (transform * xf) * (part as MeshInstance3D).get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	return bounds


# Exhaust ports in the parent's space (the engine leans about the crank), one per cylinder.
func exhaust_ports() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for p in _ports:
		out.append(transform * p)
	return out


func crank_position() -> Vector3:
	return transform * _crank_node.position if _crank_node != null else Vector3.ZERO


# crank_deg is the 0..720 cycle angle. Each piston follows its own crank pin.
func update_crank(crank_deg: float) -> void:
	if _crank_node == null:
		return
	# engine-sim turns the crank the other way round from the simulation's cycle angle, so the drawing spins that way too
	_crank_node.rotation.x = deg_to_rad(-crank_deg)
	if _balancer != null:
		_balancer.rotation.x = deg_to_rad(crank_deg) # one turn per crank turn, counter to the crank
	for i in _rods.size():
		_update_rod(i, deg_to_rad(-(crank_deg + _pin_phase[i])))
	for v in _valves:
		# the cycle angle of Cylinder: 0 is firing top dead centre, which is where this cylinder's piston is at the top with its pin phase
		var phi := fposmod(crank_deg + _pin_phase[v.cyl], 720.0)
		var lift := Cylinder.valve_lift(_spec, v.intake, phi)
		v.node.position.y = v.seat - lift * Units.M_TO_SCENE
	for c in _cams:
		c.node.rotation.x = deg_to_rad(fposmod(crank_deg + _pin_phase[c.cyl], 720.0) * 0.5)


# Real slider-crank geometry: the rod links the piston pin to its crank pin.
func _update_rod(i: int, theta: float) -> void:
	var r := _stroke * 0.5
	var x := _pin_x[i]
	var pin := Vector3(x, _crank_y + r * cos(theta), r * sin(theta))
	var wrist := Vector3(x, pin.y + sqrt(_rod_len * _rod_len - pow(r * sin(theta), 2)), 0)
	_pistons[i].position = wrist
	var d := pin - wrist
	var length := d.length()
	_rods[i].position = (pin + wrist) * 0.5
	_rods[i].quaternion = Quaternion(Vector3.UP, d.normalized()) # local +Y points from the small end to the big end
	var box: BoxMesh = _rod_shafts[i].mesh
	var size := box.size
	size.y = length
	box.size = size
	_rod_smalls[i].position = Vector3(0.0, -length * 0.5, 0.0)
	_rod_bigs[i].position = Vector3(0.0, length * 0.5, 0.0)


# The chamber's flame and spark, built inside the cylinder's own bank frame. The plug sits in the head, so its electrode
# is at the chamber roof: the flame is centred there and grows down into the bore.
func _add_combustion(bank: Node3D, x: float, bore: float, deck: float) -> void:
	var roof := deck - 0.01 # the head's underside, where the plug's electrode reaches into the charge
	var index := _flames.size()
	var piston: Node3D = _pistons.back() if not _pistons.is_empty() else null
	_flames.append(_add_flame(bank, index, Vector3(x, roof, 0.0)))
	_sparks.append(_add_spark(bank, index, Vector3(x, roof - 0.02, 0.0)))
	_spark_lights.append(_add_combustion_light(bank, index, Vector3(x, roof - 0.05, 0.0), bore))
	_spark_left.append(0.0)
	_burn_seen.append(0.0)
	_flame_level.append(0.0)
	_flame_front.append(0.0)
	_chambers.append({"bank": bank, "x": x, "roof": roof, "bore": bore, "piston": piston, "crown": PISTON_CROWN * bore})


# The flame is a disc of light the diameter of the bore and the height of the chamber, so it fills the chamber and no more
# of it: the top sits on the head, the bottom on the piston crown, and the sides just inside the barrel wall. A sphere
# sized for the look would have poked through the head and out of the barrel.
func _add_flame(bank: Node3D, index: int, at: Vector3) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = 1.0
	mesh.radial_segments = 16
	var flame := MeshInstance3D.new()
	flame.name = "Flame%d" % index
	flame.mesh = mesh
	flame.material_override = _flame_material()
	flame.position = at
	flame.scale = Vector3.ONE * 0.001
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flame.visible = false
	bank.add_child(flame)
	return flame


func _add_spark(bank: Node3D, index: int, at: Vector3) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.035
	mesh.height = 0.07
	mesh.radial_segments = 8
	mesh.rings = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(0.85, 0.95, 1.0, 1.0)
	var spark := MeshInstance3D.new()
	spark.name = "Spark%d" % index
	spark.mesh = mesh
	spark.material_override = mat
	spark.position = at
	spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spark.visible = false
	bank.add_child(spark)
	return spark


func _add_combustion_light(bank: Node3D, index: int, at: Vector3, bore: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = "CombustionLight%d" % index
	light.position = at
	light.omni_range = bore * 2.6
	light.light_color = Color(1.0, 0.72, 0.4)
	light.light_energy = 0.0
	light.shadow_enabled = false # a flash this short is not worth a shadow map, and it would flicker
	light.visible = false
	bank.add_child(light)
	return light


# One material per flame: the colour changes every frame with the gas temperature.
func _flame_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(1.0, 0.5, 0.12, 0.0)
	mat.disable_receive_shadows = true
	return mat


# Fires the flame and the spark from the simulation's own numbers. cyls are the sim's cylinders (Cylinder or
# TwoStrokeCylinder: both carry burn_energy, burn_energy_left and temp). Call after update_crank, so the chamber is where
# the piston has just put it.
func update_combustion(cyls: Array, delta: float) -> void:
	if _flames.is_empty():
		return
	for i in mini(cyls.size(), _flames.size()):
		var c = cyls[i]
		var total: float = float(c.burn_energy)
		var left: float = float(c.burn_energy_left)
		var temp: float = float(c.temp)
		var bore: float = _chambers[i].bore
		var fraction := 0.0
		if total > 1e-9:
			fraction = clampf(1.0 - left / total, 0.0, 1.0)
		# the charge lights: burn_energy_left starts falling. That instant is the spark.
		if fraction > 0.0 and _burn_seen[i] <= 0.0:
			_spark_left[i] = SPARK_FLASH_TIME
		_burn_seen[i] = fraction
		# Two things, kept apart because they are two different facts: the FRONT grows with the burned fraction (a
		# sphere of flame from the plug, sqrt of the burned mass by volume), and the BRIGHTNESS peaks part way through,
		# when the burn is fastest. The burn ends at frame N, so the glow is held for FLAME_FADE instead of snapping.
		var target := 0.0
		if fraction > 0.0 and fraction < 1.0:
			target = pow(sin(PI * fraction), 0.6)
			_flame_front[i] = sqrt(fraction)
		elif fraction <= 0.0:
			_flame_front[i] = 0.0 # the charge was reset for a new cycle
		_flame_level[i] = target if target >= _flame_level[i] else maxf(target, _flame_level[i] - delta / FLAME_FADE)
		var glow := _flame_level[i]
		var heat := clampf((temp - FLAME_COOL_K) / (FLAME_HOT_K - FLAME_COOL_K), 0.0, 1.0) if temp > 0.0 else 0.5
		var flame := _flames[i]
		flame.visible = glow > 0.01
		# contained: the chamber is between the crown at this crank angle and the head, and inside the bore
		var piston: Node3D = _chambers[i].piston
		var crown: float = float(_chambers[i].roof)
		if piston != null:
			crown = piston.position.y + float(_chambers[i].crown)
		var height := maxf(float(_chambers[i].roof) - crown, 0.004)
		var r := bore * lerpf(FLAME_MIN_SCALE, FLAME_MAX_SCALE, _flame_front[i])
		flame.scale = Vector3(maxf(r, 0.001), height, maxf(r, 0.001))
		flame.position.y = crown + height * 0.5
		var mat: StandardMaterial3D = flame.material_override
		mat.albedo_color = Color(1.0, lerpf(0.32, 0.82, heat), lerpf(0.05, 0.5, heat), glow)
		_spark_left[i] = maxf(_spark_left[i] - delta, 0.0)
		var flash := _spark_left[i] / SPARK_FLASH_TIME
		_sparks[i].visible = flash > 0.0
		# the light is the spark's flash AND the burn's glow: with the covers on, the flame is hidden inside the head but
		# the light it makes is not, so the engine flashes from the combustion rather than only from the spark plug
		_spark_lights[i].visible = flash > 0.0 or glow > 0.02
		if _spark_lights[i].visible:
			_spark_lights[i].light_energy = SPARK_LIGHT_ENERGY * maxf(flash, glow * 0.7)
			_spark_lights[i].light_color = Color(1.0, lerpf(0.5, 0.82, heat), lerpf(0.15, 0.55, heat))


# ---- what a test (or a HUD) can ask about the combustion ----
func flame_count() -> int:
	return _flames.size()


func flame_visible(i: int) -> bool:
	return i >= 0 and i < _flames.size() and _flames[i].visible


func flame_radius(i: int) -> float:
	return _flames[i].scale.x if i >= 0 and i < _flames.size() else 0.0


func flame_position(i: int) -> Vector3:
	return _flames[i].global_position if i >= 0 and i < _flames.size() else Vector3.ZERO


# Local (bank) space, so a test can see the flame is inside the chamber rather than in the head or the crankcase.
func chamber_local(i: int) -> Dictionary:
	if i < 0 or i >= _chambers.size():
		return {}
	var c: Dictionary = _chambers[i]
	var piston: Node3D = c.piston
	var crown: float = float(c.roof)
	if piston != null:
		crown = piston.position.y + float(c.crown)
	return {"crown": crown, "roof": float(c.roof), "bore": float(c.bore)}


func flame_local(i: int) -> Dictionary:
	if i < 0 or i >= _flames.size():
		return {}
	var f := _flames[i]
	return {"bottom": f.position.y - f.scale.y * 0.5, "top": f.position.y + f.scale.y * 0.5, "radius": f.scale.x}


func chamber_plug(i: int) -> Vector3:
	if i < 0 or i >= _chambers.size():
		return Vector3.ZERO
	var c: Dictionary = _chambers[i]
	return c.bank.to_global(Vector3(c.x, c.roof, 0.0))


func combustion_light_energy(i: int) -> float:
	return _spark_lights[i].light_energy if i >= 0 and i < _spark_lights.size() and _spark_lights[i].visible else 0.0


func spark_visible(i: int) -> bool:
	return i >= 0 and i < _sparks.size() and _sparks[i].visible


static func _add_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _add_cyl(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 24
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


static func iron_material() -> StandardMaterial3D:
	return _mat(Color(0.2, 0.21, 0.23), 0.48)
