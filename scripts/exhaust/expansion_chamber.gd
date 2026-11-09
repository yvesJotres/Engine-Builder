class_name ExpansionChamber
extends RefCounted

# The two-stroke expansion chamber, as pipes in the exhaust layout. Each cylinder has its own chamber, as a twin does: four
# conical sections (diffuser, baffle, convergent, stinger), each feeding the next, the stinger open to the air. The layout is
# the one the solver runs (ExhaustGas) and the one the drawing shows, so the chamber you see is the chamber that is simulated.
#
# The section proportions and radii are the ones this chamber has always used. The path is routed under the engine and out to
# the side, and fitted so its length is the spec's expansion_chamber_length_m.

const SECTION_FRACTIONS := [0.4, 0.2, 0.3, 0.1] # share of the total length in each section
const SECTION_NAMES := ["diffuser", "baffle", "convergent", "stinger"]
const SIDE_X := -1.4 # scene units, where the chamber runs back alongside the bike, clear of the rear tyre
const FIT_STEPS := 40 # bisection steps when fitting the path to the length


# The four sections of a chamber of this total length (metres): radii in metres, the walls' temperatures and the losses.
static func section_layout(total_len: float) -> Array:
	var out: Array = []
	var diff_r2 := 0.08
	var conv_r2 := 0.03
	var lens := []
	for f in SECTION_FRACTIONS:
		lens.append(total_len * f)
	out.append({"type": "divergent", "len": lens[0], "r1": 0.025, "r2": diff_r2, "temp": 900.0, "loss": 0.1})
	out.append({"type": "baffle", "len": lens[1], "r1": diff_r2, "r2": diff_r2, "temp": 850.0, "loss": 0.5})
	out.append({"type": "convergent", "len": lens[2], "r1": diff_r2, "r2": conv_r2, "temp": 800.0, "loss": 0.3})
	out.append({"type": "stinger", "len": lens[3], "r1": conv_r2, "r2": conv_r2, "temp": 700.0, "loss": 0.2})
	return out


# Adds one cylinder's chamber to layout, fed from the exhaust port (scene units, model space). Its first section is the
# cylinder's own pipe; each later section feeds the next; the last is the open end.
static func add_to(layout: ExhaustLayout, port: Vector3, cyl: int, length_m: float) -> void:
	var target := maxf(length_m, 0.05) * Units.M_TO_SCENE
	var path_of := func(e: float) -> PackedVector3Array:
		var mid_x := lerpf(port.x, SIDE_X, 0.5)
		return ExhaustLayout._spline([
			port,
			port + Vector3(0.0, -0.5, 0.35),
			Vector3(mid_x, port.y - 1.0, port.z - 0.3),
			Vector3(SIDE_X, port.y - 1.3, port.z - e * 0.5),
			Vector3(SIDE_X, port.y - 1.3, port.z - e),
		])
	var lo := 0.0
	var hi := 200.0
	for _i in FIT_STEPS:
		var mid := 0.5 * (lo + hi)
		if _length(path_of.call(mid)) < target:
			lo = mid
		else:
			hi = mid
	var pts: PackedVector3Array = path_of.call(0.5 * (lo + hi))
	var total := _length(pts)
	var sections := section_layout(length_m)
	var prev := -1
	var start := 0.0
	for k in sections.size():
		var sec: Dictionary = sections[k]
		var end_s: float = total if k == sections.size() - 1 else start + total * float(SECTION_FRACTIONS[k])
		var sub: PackedVector3Array = _slice(pts, start, end_s)
		var pipe := ExhaustLayout.Pipe.new()
		pipe.name = "chamber %d %s" % [cyl + 1, SECTION_NAMES[k]]
		pipe.kind = "chamber"
		pipe.pts = sub
		pipe.radii.resize(sub.size())
		var seg_len := maxf(end_s - start, 1e-6)
		var s_at := start
		for i in sub.size():
			var f := clampf((s_at - start) / seg_len, 0.0, 1.0)
			pipe.radii[i] = lerpf(float(sec.r1), float(sec.r2), f) * Units.M_TO_SCENE
			if i + 1 < sub.size():
				s_at += sub[i].distance_to(sub[i + 1])
		pipe.loss = ExhaustLayout.BARE_LOSS
		if k == 0:
			pipe.cyl = cyl
		if prev >= 0:
			pipe.feeders = [prev]
		prev = layout.pipes.size()
		layout.pipes.append(pipe)
		start = end_s


static func _length(pts: PackedVector3Array) -> float:
	var total := 0.0
	for i in pts.size() - 1:
		total += pts[i].distance_to(pts[i + 1])
	return total


# The part of a polyline between arc lengths a and b, with the cut points on it.
static func _slice(pts: PackedVector3Array, a: float, b: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var s := 0.0
	for i in pts.size() - 1:
		var p := pts[i]
		var q := pts[i + 1]
		var seg := p.distance_to(q)
		if s + seg >= a and s <= b:
			if out.is_empty():
				out.append(p.lerp(q, clampf((a - s) / maxf(seg, 1e-9), 0.0, 1.0)))
			if s + seg <= b:
				out.append(q)
			else:
				out.append(p.lerp(q, clampf((b - s) / maxf(seg, 1e-9), 0.0, 1.0)))
		s += seg
	if out.size() < 2:
		out = PackedVector3Array([pts[0], pts[pts.size() - 1]])
	return out
