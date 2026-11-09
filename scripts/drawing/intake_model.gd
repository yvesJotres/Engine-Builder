class_name IntakeModel
extends RefCounted


# The intake drawing: throttle bodies with their plates, velocity stacks, the fuel rail, the two-stroke carburettor and
# reed block, and the airbox. Builds into an EngineModel, which keeps the state the physics and the tank read.

const MM := Units.MM_TO_SCENE

const STACK_LENGTH := 0.35 # scene units, 35 mm velocity stack between each throttle body and the airbox

const HEAD_TO_THROTTLE := 0.3 # scene units, the throttle body sits this close to the head: the intake manifold is the long part

const STACK_FLARE := 1.45 # the stack mouth is this many times the throttle bore

const CARB_DIR := Vector3(0.0, 0.0, -1.0) # the carburettor bell faces straight back

const RUNNER_DIR := Vector3(0.0, 0.4, -0.917) # the intake runs up and back from the rear of the head, toward the airbox

const BODY_LENGTH := 0.6 # scene units, throttle body length, estimate


# Builds one four-stroke intake: the runner from the head to the throttle body, the body with its plate, and the stack.
static func build_runner(model: EngineModel, bank: Node3D, x: float, bore: float, deck: float, head_h: float, index: int, xf: Transform3D, alu: Material, steel: Material) -> void:
	# intake: a runner from the rear of the head to the throttle body, as long as the airflow model's runner
	var runner_r := sqrt(Cylinder.RUNNER_AREA / PI) * Units.M_TO_SCENE
	var throttle_r := model._spec.throttle_bore_mm * 0.5 * MM
	var port := Vector3(x, deck + head_h * 0.5, -bore * EngineModel.HEAD_RADIUS)
	var dir := RUNNER_DIR.normalized()
	# the throttle body bolts to the head, as on a real bike; the long intake manifold runs from it back to the airbox
	var at := port + dir * HEAD_TO_THROTTLE
	var intake_mark := bank.get_child_count()
	if (at - dir * BODY_LENGTH * 0.5 - port).length() > 0.05:
		_tube(bank, port, at - dir * BODY_LENGTH * 0.5, runner_r, alu) # the short port-to-body joint
	var rubber := EngineModel._mat(Color(0.06, 0.06, 0.07), 0.8)
	var body_end := at + dir * BODY_LENGTH * 0.5
	var stack_length := model._spec.velocity_stack_length_mm * MM if model._spec.intake_display == "velocity_stack" else STACK_LENGTH
	var manifold_end := at + dir * (model._spec.runner_length_m * Units.M_TO_SCENE + stack_length)
	var manifold_start := manifold_end - dir * stack_length
	_cone(bank, body_end, manifold_start, throttle_r * 1.02, throttle_r * 1.02, rubber) # the long intake manifold, one piece
	var stack_material := alu if model._spec.intake_display == "velocity_stack" else rubber
	_cone(bank, manifold_start, manifold_end, throttle_r * 1.02, throttle_r * STACK_FLARE, stack_material)
	var stack_end := manifold_end
	model._intake_mouths.append(xf * stack_end)
	model._airbox_dir = dir
	_tag_intake(bank, intake_mark)
	var body := Node3D.new() # the Y axis runs along the flow
	body.position = at
	body.quaternion = Quaternion(Vector3.UP, dir)
	bank.add_child(body)
	_open_tube(body, throttle_r + 0.04, BODY_LENGTH, EngineModel._mat(Color(0.45, 0.45, 0.48), 0.4)) # open at both ends: the bore and the plate show
	var shaft := EngineModel._add_cyl(body, 0.012, throttle_r * 3.4, Vector3.ZERO, steel) # the shaft runs through the body, its ends stick out past it
	shaft.rotation.x = PI / 2.0 # shaft across the bore
	model._plates.append(EngineModel._add_cyl(body, throttle_r * 0.95, 0.02, Vector3.ZERO, EngineModel._mat(Color(0.82, 0.83, 0.86), 0.3))) # bright plate, so it reads inside the dark bore
	model._high_points.append(xf * (at + Vector3(0.0, throttle_r + 0.1, 0.0)))
	model._injector_points.append(xf * (at + Vector3(0.0, 0.0, throttle_r + 0.04))) # nozzle on the front of each body, aimed down the runner
	if index == 0:
		model._throttle_local = xf * at
		model._injector_local = model._injector_points[0]

# A fuel rail along the nozzles, from one to the next, so the fuel reaches every injector.
static func build_fuel_rail(model: EngineModel, mat: Material) -> void:
	var intake_mark := model.get_child_count()
	for point in model._injector_points:
		_tube(model, point, point + Vector3(0.0, 0.12, 0.0), 0.025, mat)
	for i in model._injector_points.size() - 1:
		var a := model._injector_points[i] + Vector3(0.0, 0.12, 0.0)
		var b := model._injector_points[i + 1] + Vector3(0.0, 0.12, 0.0)
		_tube(model, a, b, 0.03, mat)
		EngineModel._add_cyl(model, 0.045, 0.06, (a + b) * 0.5, EngineModel._mat(Color(0.12, 0.12, 0.13), 0.5)) # the connector at each joint
	_tag_intake(model, intake_mark)

# A carburettor for a two-stroke: a flared bell at the mouth, a throttle plate across the neck, a float bowl below the body,
# and the main jet at the venturi, which is where the fuel comes out.
static func build_carburettor(model: EngineModel, bank: Node3D, x: float, bore: float, bottom: float, xf: Transform3D, index: int) -> void:
	var intake_mark := bank.get_child_count()
	var alu := EngineModel._mat(Color(0.55, 0.56, 0.6), 0.35)
	var black := EngineModel._mat(Color(0.05, 0.05, 0.05), 0.6)
	var back := Vector3(x, bottom - bore * 0.2, -bore * 0.55) # where the bell meets the reed block
	var neck := back + Vector3(0.0, 0.0, -0.3)
	var mouth := back + Vector3(0.0, 0.0, -0.8)
	_cone(bank, back, neck, bore * 0.2, bore * 0.22, alu) # the venturi throat
	_cone(bank, neck, mouth, bore * 0.22, bore * 0.4, alu) # the flared bell mouth
	EngineModel._add_cyl(bank, bore * 0.26, bore * 0.5, back + Vector3(0.0, -bore * 0.32, -0.12), alu) # the float bowl
	EngineModel._add_cyl(bank, bore * 0.09, bore * 0.18, back + Vector3(0.0, -bore * 0.1, -0.12), black) # the bowl's drain plug
	var plate := Node3D.new()
	plate.position = neck
	plate.quaternion = Quaternion(Vector3.UP, Vector3(0.0, 0.0, -1.0))
	bank.add_child(plate)
	var blade := EngineModel._add_cyl(plate, bore * 0.21, 0.02, Vector3.ZERO, black)
	var shaft := EngineModel._add_cyl(plate, 0.012, bore * 0.5, Vector3.ZERO, black)
	shaft.rotation.x = PI / 2.0
	model._plates.append(blade)
	var jet := back + Vector3(0.0, 0.0, -0.22) # main jet in the throat, above the bowl
	model._injector_points.append(xf * jet)
	model._carb_feed_points.append(xf * (back + Vector3(0.0, -bore * 0.32, -0.12 - bore * 0.26)))
	model._high_points.append(xf * (mouth + Vector3(0.0, bore * 0.4 + 0.1, 0.0)))
	model._intake_mouths.append(xf * mouth)
	model._airbox_dir = CARB_DIR
	model._airbox_gap = 0.3
	# the rubber boot from the bell to the airbox, with ribs so it reads as a flexible hose
	var rubber := EngineModel._mat(Color(0.05, 0.05, 0.05), 0.8)
	var boot_end := mouth + CARB_DIR * 0.3
	_cone(bank, mouth, boot_end, bore * 0.4, bore * 0.42, rubber)
	for k in 2:
		EngineModel._add_cyl(bank, bore * 0.44, 0.02, mouth.lerp(boot_end, 0.35 + 0.3 * k), rubber)
	# the carburettor's top cap, over the float bowl and the slide
	EngineModel._add_cyl(bank, bore * 0.2, bore * 0.12, back + Vector3(0.0, bore * 0.32, -0.12), black)
	if index == 0:
		model._throttle_local = xf * neck
		model._injector_local = xf * jet
	_tag_intake(bank, intake_mark)

# The reed valve: a cage you can see into, with three petals, each a thin plate hinged at the bottom of the cage and angled open
# toward the carburettor. The petals sit in the crankcase passage, so the cage shows them.
static func build_reed_block(model: EngineModel, bank: Node3D, x: float, bore: float, bottom: float) -> void:
	var intake_mark := bank.get_child_count()
	var cage := EngineModel._mat(Color(0.08, 0.08, 0.09), 0.55, 0.45)
	var petal := EngineModel._mat(Color(0.42, 0.44, 0.48), 0.35)
	var centre := Vector3(x, bottom - bore * 0.2, -bore * 0.35)
	EngineModel._add_box(bank, Vector3(bore * 0.5, bore * 0.3, bore * 0.4), centre, cage)
	for k in 3:
		var px := x + (k - 1) * bore * 0.16
		var holder := Node3D.new()
		holder.position = Vector3(px, bottom - bore * 0.2 - bore * 0.12, -bore * 0.2)
		holder.rotation.x = deg_to_rad(-24.0) # the petal lifts toward the carburettor
		bank.add_child(holder)
		EngineModel._add_box(holder, Vector3(bore * 0.13, bore * 0.2, bore * 0.012), Vector3(0.0, bore * 0.1, 0.0), petal)
	# the stop: a bar behind the petals that limits how far they open
	EngineModel._add_box(bank, Vector3(bore * 0.55, bore * 0.04, bore * 0.04), Vector3(x, bottom - bore * 0.2, -bore * 0.46), cage)
	_tag_intake(bank, intake_mark)

# The airbox: a housing the stacks and the carburettor mouths breathe from. Its front wall sits over the mouths, the air runs
# from a snorkel at its rear, through a paper element across the box, to the mouths. The housing is see-through, so the element
# and the stacks show. Axis-aligned, so it stays clear of the tank and the frame.
static func build_airbox(model: EngineModel, spec: EngineSpec, steel: Material) -> void:
	var intake_mark := model.get_child_count()
	var mouth_centre := Vector3.ZERO
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for m in model._intake_mouths:
		mouth_centre += m / model._intake_mouths.size()
		lo = lo.min(m)
		hi = hi.max(m)
	var back := signf(model._airbox_dir.z) if absf(model._airbox_dir.z) > 0.01 else -1.0 # the way the box lies from the mouths: back is -z for the runners
	var width := maxf(0.9, hi.x - lo.x + 0.9)
	var depth := 0.9
	var height := 0.8
	var centre := Vector3(mouth_centre.x, mouth_centre.y, mouth_centre.z + back * (depth * 0.5 - 0.05 + model._airbox_gap)) # the mouths sit 5 mm inside the front wall, or at the end of the boot
	var housing := EngineModel._mat(Color(0.12, 0.12, 0.14), 0.4, 0.85) # mostly solid, so the filter reads as sitting inside the case
	EngineModel._add_box(model, Vector3(width, height, depth), centre, housing)
	var paper := EngineModel._mat(Color(0.86, 0.8, 0.62), 0.9)
	var element_z := centre.z - back * depth * 0.2 # across the box, nearer the snorkel than the mouths
	EngineModel._add_box(model, Vector3(width * 0.84, height * 0.84, 0.1), Vector3(centre.x, centre.y, element_z), paper)
	# the snorkel: out of the rear wall, up and back to the air
	var rear := Vector3(centre.x, centre.y + height * 0.3, centre.z - back * depth * 0.5)
	var snorkel_end := rear + Vector3(0.0, 0.3, -back * 0.3)
	_tube(model, rear, snorkel_end, 0.12, steel)
	EngineModel._add_cyl(model, 0.14, 0.04, snorkel_end, steel) # the lip of the snorkel
	if model._airbox_gap == 0.0:
		# ram-air duct: from the top front of the airbox, forward and up to the air under the screen
		var duct_start := Vector3(centre.x, centre.y + height * 0.5, centre.z - back * depth * 0.4)
		var duct_end := duct_start + Vector3(0.0, 0.25, -back * 0.7)
		_tube(model, duct_start, duct_end, 0.1, steel)
		EngineModel._add_cyl(model, 0.12, 0.04, duct_end, steel) # the mouth of the duct
	_tag_intake(model, intake_mark)

# A tube along the node's Y axis with no end caps, so its bore is open at both ends. Two-sided, so the inside shows.
static func _open_tube(parent: Node3D, radius: float, height: float, mat: Material) -> MeshInstance3D:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var segments := 24
	for i in segments + 1:
		var angle := TAU * float(i) / segments
		var n := Vector3(cos(angle), 0.0, sin(angle))
		for y in [-height * 0.5, height * 0.5]:
			verts.append(n * radius + Vector3(0.0, y, 0.0))
			normals.append(n)
	for i in segments:
		var a := i * 2
		var b := a + 1
		var c := a + 2
		var d := a + 3
		indices.append_array([a, b, c, b, d, c])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var two_sided := mat.duplicate() as StandardMaterial3D
	two_sided.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = two_sided
	parent.add_child(mi)
	return mi

# A cone from a to b: radius r1 at a, r2 at b.
static func _cone(parent: Node3D, a: Vector3, b: Vector3, r1: float, r2: float, mat: Material) -> void:
	var dir := b - a
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = r1
	mesh.top_radius = r2
	mesh.height = dir.length()
	mesh.radial_segments = 24
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = (a + b) * 0.5
	mi.quaternion = Quaternion(Vector3.UP, dir.normalized())
	parent.add_child(mi)

static func _tube(parent: Node3D, a: Vector3, b: Vector3, radius: float, mat: Material) -> void:
	var dir := b - a
	var mi := EngineModel._add_cyl(parent, radius, dir.length(), (a + b) * 0.5, mat)
	mi.quaternion = Quaternion(Vector3.UP, dir.normalized())

# Marks the nodes added to parent since from_count as intake, so the intake can be shown on its own.
static func _tag_intake(parent: Node, from_count: int) -> void:
	for i in range(from_count, parent.get_child_count()):
		parent.get_child(i).set_meta("intake", true)
