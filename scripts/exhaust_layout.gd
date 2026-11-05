class_name ExhaustLayout
extends RefCounted

# The exhaust as a list of pipes routed through the scene. The drawing (Exhaust) and the sound (EngineSound) both read
# this, so the pipe you see is the pipe you hear: lengths and cross-sections come from the same path.
# Scene units: 1 unit = 10 cm. Pipes are listed upstream first, and the last one is the tailpipe, open to the air.
# Shapes and sizes are estimates for a small sport bike, not measured from a K45R exhaust.

const M := Units.M_TO_SCENE
const GROUND_CLEARANCE := 1.6 # 160 mm, the best-supported K45R figure (research notes)
const PRIMARY_R := 0.16 # 32 mm tube
const SECONDARY_R := 0.19
const COLLECTOR_R := 0.2 # 40 mm
const CAT_R := 0.32 # catalytic converter shell, 64 mm
const MUFFLER_R := 0.55 # canister, 110 mm
const MUFFLER_LEN := 3.8
const TAIL_R := 0.17
const TAIL_LEN := 0.45
const MUFFLER_RISE := 0.14 # canister climbs toward the back, per unit of length
const TYRE_HALF_WIDTH := 0.65
# amplitude lost per metre travelled: friction and heat for bare pipe, much more through the catalyst and the packed muffler
const BARE_LOSS := 0.25
const CAT_LOSS := 4.0
const MUFFLER_LOSS := 1.5


class Pipe:
	var name := ""
	var kind := "" # primary | secondary | collector | catalyst | mid | muffler | tail
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array() # scene units, one per point
	var cyl := -1 # primary only: the cylinder feeding it
	var feeders: Array[int] = [] # pipes that join at this pipe's upstream end
	var loss := BARE_LOSS # 1/m, amplitude loss along the pipe

	func length_m() -> float:
		var total := 0.0
		for i in pts.size() - 1:
			total += pts[i].distance_to(pts[i + 1])
		return total / M

	# Mean cross-section, weighted by length (a cone averages r1² + r1·r2 + r2²).
	func area_m2() -> float:
		var sum := 0.0
		var len_sum := 0.0
		for i in pts.size() - 1:
			var seg := pts[i].distance_to(pts[i + 1])
			var r1 := radii[i] / M
			var r2 := radii[i + 1] / M
			sum += seg * (r1 * r1 + r1 * r2 + r2 * r2) / 3.0
			len_sum += seg
		return PI * sum / maxf(len_sum, 1e-9)


var pipes: Array[Pipe] = []


# ports: exhaust port per cylinder in world space, facing forward. crank and axle: world positions of the crank and the
# rear axle. Without ports the layout is built for a standard engine position, which is enough for the sound alone.
static func build(spec: EngineSpec, ports: Array[Vector3] = [], crank := Vector3(0.0, 0.92, 0.0),
		ground_y := Ground.Y, axle := Vector3.ZERO) -> ExhaustLayout:
	var tyre_r := Drivetrain.tire_outer_radius()
	if axle == Vector3.ZERO:
		axle = Vector3(0.0, ground_y + tyre_r, -5.95)
	var n := spec.cylinders
	if ports.is_empty():
		var pitch := spec.bore_mm * Units.MM_TO_SCENE * EngineModel.PITCH_FACTOR
		for i in n:
			ports.append(Vector3(-(n - 1) * pitch * 0.5 + i * pitch, crank.y + 1.5, 0.55))
	var layout := ExhaustLayout.new()
	var low_y := ground_y + GROUND_CLEARANCE + CAT_R # the pipes run under the engine, their lowest point at the ground clearance
	var centre_x := 0.0
	for p in ports:
		centre_x += p.x / n
	var sec_pairs := spec.header == "4-2-1" and n >= 3
	var long_primaries := spec.header != "stock"
	# the collector point: close under the engine for the stock manifold, further back for a long-primary header
	var collector := Vector3(centre_x - 0.35, low_y, crank.z + (-1.1 if sec_pairs else (-0.9 if long_primaries else 0.1)))
	# the pipe must be out beside the tyre before it reaches the tyre's front edge, so with little room (a long header
	# puts the collector far back) the whole run moves out to the side early
	var muffler_x := -(TYRE_HALF_WIDTH + MUFFLER_R + 0.12)
	var tyre_front_z := axle.z + sqrt(maxf(tyre_r * tyre_r - (low_y - axle.y) * (low_y - axle.y), 0.0))
	var run_back := (0.7 if n > 1 else 0.0) + 1.55
	if collector.z - run_back - (tyre_front_z + 0.3) < 1.2:
		collector.x = muffler_x * 0.8

	var groups: Array = [range(n)]
	if sec_pairs:
		groups = [range(ceili(n / 2.0)), range(ceili(n / 2.0), n)]

	var radius := PRIMARY_R if long_primaries else PRIMARY_R * 0.92
	var group_ends: Array[Vector3] = []
	for g in groups:
		var gx := 0.0
		for idx in g:
			gx += ports[idx].x / g.size()
		# a group merges just ahead of the collector point when it is a pair, or at the collector point itself
		var merge := collector if groups.size() == 1 else Vector3(lerpf(gx, collector.x, 0.5), low_y + 0.1, crank.z - 0.5)
		group_ends.append(merge)
		for idx in g:
			var p: Vector3 = ports[idx]
			var ctrl := [
				p,
				p + Vector3(0.0, -0.12, 0.35),
				Vector3(lerpf(p.x, merge.x, 0.1), p.y - 0.85, p.z + 0.85),
				Vector3(lerpf(p.x, merge.x, 0.35), low_y + 0.15, p.z + 0.6),
				Vector3(lerpf(p.x, merge.x, 0.8), low_y, merge.z + 0.5),
				merge,
			]
			var pipe := _pipe("primary %d" % (idx + 1), "primary", _spline(ctrl), radius)
			pipe.cyl = idx
			layout.pipes.append(pipe)

	var feed: Array[int] = []
	for i in layout.pipes.size():
		feed.append(i)
	if groups.size() > 1:
		var secondaries: Array[int] = []
		for gi in groups.size():
			var a: Vector3 = group_ends[gi]
			var mid := a.lerp(collector, 0.5) + Vector3(0.0, -0.03, 0.0)
			var pipe := _pipe("secondary %d" % (gi + 1), "secondary", _spline([a, mid, collector]), SECONDARY_R)
			for i in layout.pipes.size():
				if layout.pipes[i].kind == "primary" and layout.pipes[i].pts[-1].is_equal_approx(a):
					pipe.feeders.append(i)
			secondaries.append(layout.pipes.size())
			layout.pipes.append(pipe)
		feed = secondaries

	var back := Vector3(0.0, 0.0, -1.0)
	var start := collector
	if n > 1:
		var pipe := _pipe("collector", "collector", PackedVector3Array([start, start + back * 0.7]), COLLECTOR_R)
		pipe.feeders = feed
		layout.pipes.append(pipe)
		feed = [layout.pipes.size() - 1]
		start += back * 0.7

	# catalytic converter: a short fat canister in the line
	var cat := _axial("catalyst", "catalyst", start, back, [0.0, 0.25, 0.3, 1.25, 1.3, 1.55],
			[COLLECTOR_R, CAT_R, CAT_R, CAT_R, CAT_R, COLLECTOR_R])
	cat.loss = CAT_LOSS
	cat.feeders = feed
	layout.pipes.append(cat)
	var cat_end := start + back * 1.55

	# the muffler sits beside the rear tyre, rising a little toward the back
	var dir := Vector3(0.0, MUFFLER_RISE, -1.0).normalized()
	var m0 := Vector3(muffler_x, low_y + 0.3, minf(axle.z + tyre_r + 0.1, cat_end.z - 1.2))
	var mid := _pipe("mid pipe", "mid", _spline([
		cat_end,
		cat_end + back * 0.3,
		Vector3(lerpf(cat_end.x, m0.x, 0.55), low_y + 0.08, lerpf(cat_end.z, m0.z, 0.55)),
		m0 - dir * 0.5,
		m0,
	]), COLLECTOR_R)
	mid.feeders = [layout.pipes.size() - 1]
	layout.pipes.append(mid)

	var muffler := _axial("muffler", "muffler", m0, dir, [0.0, 0.4, 0.42, MUFFLER_LEN - 0.42, MUFFLER_LEN - 0.4, MUFFLER_LEN],
			[COLLECTOR_R, MUFFLER_R, MUFFLER_R, MUFFLER_R, MUFFLER_R, 0.3])
	muffler.loss = MUFFLER_LOSS
	muffler.feeders = [layout.pipes.size() - 1]
	layout.pipes.append(muffler)

	var tail := _axial("tailpipe", "tail", m0 + dir * MUFFLER_LEN, dir, [0.0, TAIL_LEN], [TAIL_R, TAIL_R])
	tail.feeders = [layout.pipes.size() - 1]
	layout.pipes.append(tail)
	return layout


# Sum of all pipe lengths, metres. A change in it tells the caller the sound must be rebuilt.
func total_length_m() -> float:
	var total := 0.0
	for p in pipes:
		total += p.length_m()
	return total


static func _pipe(pipe_name: String, kind: String, pts: PackedVector3Array, radius: float) -> Pipe:
	var pipe := Pipe.new()
	pipe.name = pipe_name
	pipe.kind = kind
	pipe.pts = pts
	pipe.radii.resize(pts.size())
	pipe.radii.fill(radius)
	return pipe


# A straight pipe along dir whose radius changes at the given distances from start.
static func _axial(pipe_name: String, kind: String, start: Vector3, dir: Vector3, at: Array, radii: Array) -> Pipe:
	var pipe := Pipe.new()
	pipe.name = pipe_name
	pipe.kind = kind
	for i in at.size():
		pipe.pts.append(start + dir * at[i])
		pipe.radii.append(radii[i])
	return pipe


# Smooth curve through the control points (Catmull-Rom), so the pipe bends instead of kinking.
static func _spline(ctrl: Array, per_seg := 8) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := ctrl.size()
	for i in n - 1:
		var p0: Vector3 = ctrl[maxi(i - 1, 0)]
		var p1: Vector3 = ctrl[i]
		var p2: Vector3 = ctrl[i + 1]
		var p3: Vector3 = ctrl[mini(i + 2, n - 1)]
		for k in per_seg:
			var t := float(k) / per_seg
			out.append(0.5 * (2.0 * p1 + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t * t * t))
	out.append(ctrl[n - 1])
	return out
