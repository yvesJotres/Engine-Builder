class_name Sprocket
extends RefCounted

# Toothed sprocket generator, following the standard roller chain geometry:
# - pitch circle radius P / (2·sin(180°/N)), where P is the chain pitch and N the tooth count
# - tip (outside) diameter P·(0.6 + cot(180°/N))
# - a roller seat curve centred on each roller position on the pitch circle, facing the centre
# Tooth flanks are simplified; this is a visual model, not a manufacturing drawing.

const ROLLER_RADIUS := 0.0388 # scene units, 7.75 mm roller diameter ÷ 2
const SEAT_SCALE := 1.02 # seat radius is slightly larger than the roller
const SEAT_POINTS := 7 # points along each roller seat
const SEAT_SPAN := 0.9 # radians of seat on each side of the roller's inward direction


# Pitch circle radius of the sprocket, scene units.
static func pitch_radius(teeth: int) -> float:
	return Drivetrain.sprocket_radius(teeth)


# Tip (outside) radius, scene units: outside diameter P·(0.6 + cot(180°/N)) / 2.
static func tip_radius(teeth: int) -> float:
	return Drivetrain.CHAIN_PITCH * (0.6 + 1.0 / tan(PI / teeth)) * 0.5


# Outline in the XY plane, sorted by polar angle so it forms one closed star around the centre.
static func outline(teeth: int) -> PackedVector2Array:
	var pitch_r := pitch_radius(teeth)
	var tip_r := tip_radius(teeth)
	var seat_r := ROLLER_RADIUS * SEAT_SCALE
	var step := TAU / teeth
	var pts: Array = []
	for i in teeth:
		var a := i * step
		# tooth tip, two corners
		pts.append(Vector2.from_angle(a - 0.12 * step) * tip_r)
		pts.append(Vector2.from_angle(a + 0.12 * step) * tip_r)
		# roller seat for the roller that sits between this tooth and the next
		var b := a + 0.5 * step
		var centre := Vector2.from_angle(b) * pitch_r
		for j in SEAT_POINTS:
			var phi := lerpf(-SEAT_SPAN, SEAT_SPAN, float(j) / (SEAT_POINTS - 1))
			pts.append(centre + Vector2.from_angle(b + PI + phi) * seat_r)
	pts.sort_custom(func(p: Vector2, q: Vector2) -> bool: return atan2(p.y, p.x) < atan2(q.y, q.x))
	return PackedVector2Array(pts)


# A sprocket solid, thickness along X so it sits on the chain plane.
static func build(teeth: int, thickness: float, mat: Material) -> CSGPolygon3D:
	var csg := CSGPolygon3D.new()
	csg.polygon = outline(teeth)
	csg.mode = CSGPolygon3D.MODE_DEPTH
	csg.depth = thickness
	csg.material = mat
	csg.rotation.y = PI / 2.0 # extrude along X
	return csg
