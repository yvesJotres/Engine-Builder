extends SceneTree

# Two closed-form rows of docs/physics-validation.md section 2 that had no test.
#
# 1. Volume against crank angle, slider-crank. With r = stroke/2 and L = rod_ratio * r,
#      V(theta) = Vc + A * [ r(1 - cos) + L - sqrt(L^2 - r^2 sin^2) ]
#    so V(0) = clearance, V(180) = clearance + swept, and V(90) is the term above with cos = 0, sin = 1.
# 2. Wiebe burn fraction,  x = 1 - exp(-a * ((theta - theta0) / dtheta)^(m+1)),  a = 6.908, m = 2,
#    which by construction reaches 1 - exp(-6.908) = 0.999 of the charge at the end of the burn.
#
# Both are definitions with stated constants, so the expected values are worked out here and the code is only asked for
# its answer. Tag [closed].
# Run: godot --headless --path . -s res://tests/unit/engine/cylinder_geometry_test.gd   (exit 1 on failure)

const BORE := 0.062
const STROKE := 0.0413
const CR := 11.5
const ROD_RATIO := 1.6 # rod length over crank radius, the cylinder's convention
const WIEBE_A := 6.908
const WIEBE_M := 2.0

var _fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL " + msg)


static func near(a: float, b: float, tol: float = 1.0e-9) -> bool:
	return absf(a - b) <= tol * maxf(1.0, absf(b))


func _init() -> void:
	var cyl := Cylinder.new()
	cyl.setup(BORE * 1000.0, STROKE * 1000.0, CR)
	cyl.rod_ratio = ROD_RATIO
	var area := PI * 0.25 * BORE * BORE
	var r := STROKE * 0.5
	var l := ROD_RATIO * r
	var vs := area * STROKE
	print("bore %.1f mm, stroke %.1f mm, swept %.2f cc, clearance %.2f cc, CR %.2f" % [
		cyl.bore * 1000.0, cyl.stroke * 1000.0, cyl.swept * 1.0e6, cyl.clearance * 1.0e6,
		(cyl.clearance + cyl.swept) / cyl.clearance])

	# ---- 1. the three exact points of the slider-crank ----
	check(near(cyl.volume(0.0), cyl.clearance), "V(0) is the clearance volume (%.12f vs %.12f m3)" % [cyl.volume(0.0), cyl.clearance])
	check(near(cyl.volume(180.0), cyl.clearance + vs),
		"V(180) is clearance + swept (%.12f vs %.12f m3)" % [cyl.volume(180.0), cyl.clearance + vs])
	var want_90 := cyl.clearance + area * (r + l - sqrt(l * l - r * r))
	check(near(cyl.volume(90.0), want_90), "V(90) matches r + L - sqrt(L^2 - r^2) (%.12f vs %.12f m3)" % [cyl.volume(90.0), want_90])
	check(near(cyl.volume(360.0), cyl.clearance), "V(360) is back at the clearance volume")

	# ---- 2. the geometry's own consistencies ----
	check(near((cyl.clearance + cyl.swept) / cyl.clearance, CR, 1.0e-9), "clearance and swept reproduce the compression ratio")
	var symmetric := true
	for deg in [30.0, 60.0, 90.0, 120.0, 150.0]:
		if not near(cyl.volume(deg), cyl.volume(360.0 - deg)):
			symmetric = false
	check(symmetric, "the volume is symmetric about TDC: V(t) == V(360 - t)")
	var rising := true
	var previous := cyl.volume(0.0)
	for deg in range(1, 181, 5):
		var v := cyl.volume(float(deg))
		if v < previous - 1.0e-15:
			rising = false
		previous = v
	check(rising, "the volume only grows from TDC to BDC")

	# ---- 3. Wiebe: the stated endpoints and the shape ----
	check(cyl._wiebe(0.0, 90.0) == 0.0, "nothing is burnt at the spark")
	var end := 1.0 - exp(-WIEBE_A)
	check(near(cyl._wiebe(90.0, 90.0), end), "the end of the burn is 1 - exp(-a) = %.6f (%.6f)" % [end, cyl._wiebe(90.0, 90.0)])
	var half_window := 1.0 - exp(-WIEBE_A * pow(0.5, WIEBE_M + 1.0))
	check(near(cyl._wiebe(45.0, 90.0), half_window),
		"half way through the window burns %.6f of the charge (%.6f)" % [half_window, cyl._wiebe(45.0, 90.0)])
	var third := 1.0 - exp(-WIEBE_A * pow(1.0 / 3.0, WIEBE_M + 1.0))
	check(near(cyl._wiebe(30.0, 90.0), third), "a third of the window burns %.6f (%.6f)" % [third, cyl._wiebe(30.0, 90.0)])

	# ---- 4. Wiebe is a function of the fraction burnt through the window, not of absolute degrees ----
	check(near(cyl._wiebe(45.0, 90.0), cyl._wiebe(90.0, 180.0)),
		"the same fraction of a longer window burns the same share")

	# ---- 5. and it is monotone and bounded ----
	var monotone := true
	var last := -1.0
	for deg in range(0, 181, 3):
		var x := cyl._wiebe(float(deg), 180.0)
		if x < last or x > 1.0:
			monotone = false
		last = x
	check(monotone, "the burnt fraction only rises and never exceeds 1")
	check(cyl._wiebe(400.0, 180.0) <= 1.0, "past the window it stays clamped at 1")

	print("V(0) %.12f, V(90) %.12f, V(180) %.12f m3; Wiebe(45/90) %.6f, end %.6f" % [
		cyl.volume(0.0), cyl.volume(90.0), cyl.volume(180.0), cyl._wiebe(45.0, 90.0), end])
	print("RESULT: " + ("FAIL" if _fails > 0 else "PASS"))
	quit(1 if _fails > 0 else 0)
