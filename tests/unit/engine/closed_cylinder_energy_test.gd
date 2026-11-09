extends SceneTree

# Closed, adiabatic cylinder: gas work must equal the decrease in internal energy.
func _init() -> void:
	Cylinder.use_native = OS.get_cmdline_user_args().has("--native")
	if Cylinder.use_native and not Cylinder.native_available:
		push_error("Native energy check requires CylinderKernel")
		quit(2)
		return
	var c := Cylinder.new()
	c.setup(62.0, 41.3, 11.5)
	c.intake_lift = 0.0
	c.exhaust_lift = 0.0
	c.wall_heat_scale = 0.0
	c.recip_kg = 0.0
	c.start_at(180.0) # Start at BDC so adiabatic expansion stays above the temperature floor.
	var tank := FuelTank.new()
	var initial_energy := c._u
	var work := 0.0
	for i in 720:
		var result := c.advance(1.0, 1.0 / 6000.0, Cylinder.P0, Cylinder.T0, 700.0, false, tank, 1.0, false)
		work += result.x * PI / 180.0
	var residual := absf(c._u - initial_energy + work)
	print("Closed-cylinder energy residual: %.8f J" % residual)
	var ok := residual < 0.0001
	print("RESULT: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
