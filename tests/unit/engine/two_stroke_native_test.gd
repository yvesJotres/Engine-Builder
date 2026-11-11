extends SceneTree

# The native two-stroke kernel (gdextension/src/two_stroke_kernel.cpp) must give the same answers as TwoStrokeCylinder.advance.
# A GDScript TwoStrokeCylinder and a TwoStrokeKernel state array are advanced with identical inputs through a start, part
# throttle, wide open, a lean misfire, a limiter cut and a spark cut, on a reed and a piston-port intake. After every step the
# returned work and every state field are compared to REL_TOL. Phi is wrapped back into 0..360 in both after each step, because the
# GDScript's port-event test uses the raw angle and would otherwise stop firing after the first turn.
# Prints FAIL lines and exits non-zero on a mismatch; exits 2 if the TwoStrokeKernel class is not loaded.
# Run: godot --headless --path . -s tests/unit/engine/two_stroke_native_test.gd
const PRESET := "yamaha_rd350"
const REL_TOL := 1.0e-6
const P0 := 101325.0
# exhaust_mdot and exhaust_power are the flow of the last sub-step only. When the cylinder and exhaust pressures are nearly equal
# that is a sqrt of the difference of two nearly equal powers, so a one-ulp difference in pow() between the two builds shows
# at about 1e-10. Everything else is held to REL_TOL.
# Measured: the largest relative error seen on these fields is about 2e-6 (piston step 85), from pow() rounding where the
# pressures are nearly equal. Set to 1e-5, about 5x that. Every other field is held to REL_TOL.
const LOOSE := ["exhaust_mdot", "exhaust_power"]
const LOOSE_TOL := 1.0e-5
# Mirrors TwoStrokeKernel::StateIndex in gdextension/include/two_stroke_kernel.h, in order.
const STATE := ["phi", "mass", "temp", "pressure", "burn_energy_left", "burn_energy", "port_p", "runner_q", "exhaust_temp",
	"peak_temp", "last_peak_temp", "last_lambda", "fired", "fuel_unburnt_kg", "port_heat", "backfire_j", "residual_kg",
	"overlap_out", "burnt", "wall_loss_j", "u", "enthalpy_in_j", "enthalpy_out_j", "exhaust_mdot", "exhaust_power",
	"cycle_work", "cycle_deg", "cycle_peak_p", "cycle_max_dp", "cycle_p", "ca10", "ca50", "ca90", "last_imep",
	"last_peak_pressure", "last_dp_dtheta", "last_ca10", "last_ca50", "last_ca90", "last_burn_10_90", "last_fresh_kg",
	"last_ivc_temp", "last_residual_fraction", "crankcase_mass", "crankcase_temp", "crankcase_pressure",
	"oil_in_crankcase_kg", "tank_mass", "out_work", "out_fuel"]
# the GDScript keeps these under a leading underscore
const PRIVATE := ["fired", "port_heat", "residual_kg", "overlap_out", "burnt", "u", "cycle_work", "cycle_deg", "cycle_peak_p",
	"cycle_max_dp", "cycle_p", "ca10", "ca50", "ca90"]
# rpm, manifold pressure (x P0), lambda, spark, limiter cut, exhaust pressure (x P0), exhaust temp, ignition phase, frames
const SCRIPT := [
	[7000.0, 1.0, 0.9, true, false, 1.5, 800.0, 340.0, 60],
	[300.0, 0.95, 1.0, true, false, 1.0, 300.0, 350.0, 40],
	[3000.0, 0.5, 1.0, true, false, 1.2, 600.0, 345.0, 60],
	[5000.0, 0.8, 1.5, true, false, 1.0, 300.0, 350.0, 20],
	[7000.0, 1.0, 1.0, true, true, 1.3, 700.0, 350.0, 20],
	[4000.0, 0.7, 1.0, false, false, 1.0, 300.0, 350.0, 30],
	[6000.0, 0.9, 1.0, true, false, 1.4, 750.0, 350.0, 40],
]
const DT := 1.0 / 120.0

var failures := 0


func _init() -> void:
	await process_frame
	if not ClassDB.class_exists("TwoStrokeKernel"):
		print("SKIP: the TwoStrokeKernel class is not loaded, nothing to compare")
		quit(2)
		return
	if TwoStrokeKernel.state_size() != STATE.size():
		print("FAIL state_size is %d, this test lists %d fields" % [TwoStrokeKernel.state_size(), STATE.size()])
		quit(1)
		return
	for port in ["reed", "piston"]:
		_compare(port)
	print("two_stroke_native_test: %s" % ("PASSED" if failures == 0 else "FAILED (%d problems)" % failures))
	quit(0 if failures == 0 else 1)


func _gd_name(n: String) -> String:
	return "_" + n if PRIVATE.has(n) else n


func _config(c: TwoStrokeCylinder) -> PackedFloat64Array:
	var type := 0.0
	if c.intake_port_type == "reed":
		type = 1.0
	elif c.intake_port_type == "rotary" or c.intake_port_type == "piston":
		type = 2.0
	return PackedFloat64Array([c.bore, c.piston_area, c.stroke, c.swept, c.clearance, c.recip_kg, c.rod_ratio, c.transfer_open,
		c.transfer_close, c.exhaust_open, c.exhaust_close, c.intake_open, c.intake_close, c.transfer_area, c.exhaust_area,
		c.intake_area, c.crankcase_volume, c.oil_ratio, type, c.crank_radius])


func _state(c: TwoStrokeCylinder, tank: FuelTank) -> PackedFloat64Array:
	var s := PackedFloat64Array()
	s.resize(STATE.size())
	for i in STATE.size():
		var n: String = STATE[i]
		if n == "tank_mass":
			s[i] = tank.mass_kg
		elif n != "out_work" and n != "out_fuel":
			s[i] = float(c.get(_gd_name(n)))
	return s


func _close(a: float, b: float, tol: float = REL_TOL) -> bool:
	return absf(a - b) <= tol * maxf(1.0e-9, maxf(absf(a), absf(b)))


func _compare(port: String) -> void:
	var spec := EngineSpec.new()
	var p: Dictionary = Presets.PRESETS[PRESET]
	for key in p.keys():
		spec.set(key, p[key])
	spec.intake_port_type = port
	var cyl := TwoStrokeCylinder.new()
	cyl.setup(spec)
	cyl.start_at(0.0)
	var tank := FuelTank.new()
	var cfg := _config(cyl)
	var state := _state(cyl, tank)
	var step := 0
	var bad := 0
	for stage in SCRIPT:
		var dphi: float = stage[0] * 6.0 * DT
		for f in int(stage[8]):
			var res: Vector2 = cyl.advance(dphi, DT, stage[1] * P0, 300.0, stage[7], true, tank, stage[2], stage[3], stage[4],
				stage[5] * P0, stage[6])
			state = TwoStrokeKernel.advance(state, cfg, dphi, DT, stage[1] * P0, 300.0, stage[7], true, tank.afr, tank.lhv,
				stage[2], stage[3], stage[4], stage[5] * P0, stage[6])
			if not _close(res.x, state[STATE.find("out_work")]):
				bad += 1
				print("FAIL %s step %d work: gdscript %s native %s" % [port, step, str(res.x), str(state[STATE.find("out_work")])])
			for i in STATE.size():
				var n: String = STATE[i]
				if n == "out_work" or n == "out_fuel":
					continue
				var want: float = tank.mass_kg if n == "tank_mass" else float(cyl.get(_gd_name(n)))
				if not _close(want, state[i], LOOSE_TOL if LOOSE.has(n) else REL_TOL):
					bad += 1
					print("FAIL %s step %d %s: gdscript %s native %s" % [port, step, n, str(want), str(state[i])])
			if bad > 0:
				break
			if state[STATE.find("out_fuel")] != res.y:
				bad += 1
				print("FAIL %s step %d fuel consumed: gdscript %s native %s" % [port, step, str(res.y), str(state[STATE.find("out_fuel")])])
				break
			# keep phi in 0..360 on both sides
			if cyl.phi >= 360.0:
				cyl.phi -= 360.0
				state[0] -= 360.0
			# Start the next step from the GDScript's state: the model amplifies rounding (sqrt of a pressure difference near zero,
			# a power of a pressure ratio near 1), so a free run would only measure how chaotic it is, not whether the port is right.
			state = _state(cyl, tank)
			step += 1
		if bad > 0:
			break
	failures += bad
	print("%s: %d steps, %d problems" % [port, step, bad])
