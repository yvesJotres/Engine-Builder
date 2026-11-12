extends SceneTree

# Where do the two builds start to differ on a reed intake? Mirrors tests/unit/engine/two_stroke_native_test.gd for the
# reed path and prints the first step at which a field drifts past 1e-9 relative, with the three steps before it.
# Run: godot --headless --path . -s res://tools/diagnostics/probe_parity_reed.gd

const PRESET := "yamaha_rd350"
const P0 := 101325.0
const DT := 1.0 / 120.0
const FIELDS := ["crankcase_mass", "crankcase_pressure", "crankcase_temp", "temp", "pressure", "mass", "u",
	"residual_kg", "fresh_in_kg", "last_fresh_kg"]
# Mirrors TwoStrokeKernel::StateIndex, in order.
const NAMES := ["phi", "mass", "temp", "pressure", "burn_energy_left", "burn_energy", "port_p", "runner_q",
	"exhaust_temp", "peak_temp", "last_peak_temp", "last_lambda", "fired", "fuel_unburnt_kg", "port_heat",
	"backfire_j", "residual_kg", "overlap_out", "burnt", "wall_loss_j", "u", "enthalpy_in_j", "enthalpy_out_j",
	"exhaust_mdot", "exhaust_power", "cycle_work", "cycle_deg", "cycle_peak_p", "cycle_max_dp", "cycle_p",
	"ca10", "ca50", "ca90", "last_imep", "last_peak_pressure", "last_dp_dtheta", "last_ca10", "last_ca50",
	"last_ca90", "last_burn_10_90", "last_fresh_kg", "last_ivc_temp", "last_residual_fraction", "crankcase_mass",
	"crankcase_temp", "crankcase_pressure", "oil_in_crankcase_kg", "tank_mass", "out_work", "out_fuel", "fresh_in_kg"]
var _reported := false
const SCRIPT := [
	[7000.0, 1.0, 0.9, true, false, 1.5, 800.0, 340.0, 60],
	[300.0, 0.95, 1.0, true, false, 1.0, 300.0, 350.0, 40],
	[3000.0, 0.5, 1.0, true, false, 1.2, 600.0, 345.0, 60],
	[5000.0, 0.8, 1.5, true, false, 1.0, 300.0, 350.0, 20],
	[7000.0, 1.0, 1.0, true, true, 1.3, 700.0, 350.0, 20],
	[4000.0, 0.7, 1.0, false, false, 1.0, 300.0, 350.0, 30],
	[6000.0, 0.9, 1.0, true, false, 1.4, 750.0, 350.0, 40],
]


func _init() -> void:
	await process_frame
	var spec := EngineSpec.new()
	var p: Dictionary = Presets.PRESETS[PRESET]
	for key in p.keys():
		spec.set(key, p[key])
	spec.intake_port_type = "reed"
	var cyl := TwoStrokeCylinder.new()
	cyl.setup(spec)
	cyl.start_at(0.0)
	var tank := FuelTank.new()
	var type := 1.0
	# Same order as TwoStrokeKernel::CfgIndex. An array shorter than C_SIZE makes advance() return its input untouched,
	# which reads as a frozen engine rather than an error.
	var cfg := PackedFloat64Array([cyl.bore, cyl.piston_area, cyl.stroke, cyl.swept, cyl.clearance, cyl.recip_kg,
		cyl.rod_ratio, cyl.transfer_open, cyl.transfer_close, cyl.exhaust_open, cyl.exhaust_close, cyl.intake_open,
		cyl.intake_close, cyl.transfer_area, cyl.exhaust_area, cyl.intake_area, cyl.crankcase_volume, cyl.oil_ratio,
		1.0, cyl.crank_radius])
	var state := _state(cyl, tank)
	var step := 0
	var history: Array = []
	var worst := {}
	for stage in SCRIPT:
		var dphi: float = stage[0] * 6.0 * DT
		for f in int(stage[8]):
			var res: Vector2 = cyl.advance(dphi, DT, stage[1] * P0, 300.0, stage[7], true, tank, stage[2], stage[3],
				stage[4], stage[5] * P0, stage[6])
			state = TwoStrokeKernel.advance(state, cfg, dphi, DT, stage[1] * P0, 300.0, stage[7], true, tank.afr,
				tank.lhv, stage[2], stage[3], stage[4], stage[5] * P0, stage[6])
			if step == 0:
				print("after 1 call: native phi=%.3f mass=%.9f temp=%.2f crankcase=%.9f | gd phi=%.3f mass=%.9f" % [
					state[0], state[1], state[2], state[43], cyl.phi, cyl.mass])
			var row := "step %3d phi %7.2f" % [step, cyl.phi]
			var drifted := false
			for n in FIELDS:
				var priv_names := ["u", "residual_kg", "fresh_in_kg"]
				var want: float = float(cyl.get("_" + n if priv_names.has(n) else n))
				var got: float = float(state[NAMES.find(n)])
				var rel: float = absf(want - got) / maxf(1.0e-9, maxf(absf(want), absf(got)))
				row += " | " + n + " " + str(want) + " vs " + str(got) + " (" + str(rel) + ")"
				if rel > float(worst.get(n, 0.0)):
					worst[n] = rel
				if rel > 1.0e-9:
					drifted = true
			history.append(row)
			if drifted and not _reported:
				_reported = true
				print("FIRST DRIFT at step %d" % step)
				for h in history.slice(-2):
					print(h)
			step += 1
			if cyl.phi >= 360.0:
				cyl.phi -= 360.0
				state[0] -= 360.0
	print("ran %d steps" % step)
	for n in worst:
		print("  worst rel " + n + " = " + str(float(worst[n])))
	quit(0)


func _idx(n: String) -> int:
	return NAMES.find(n)


func _state(c: TwoStrokeCylinder, tank: FuelTank) -> PackedFloat64Array:
	var priv := ["fired", "port_heat", "residual_kg", "fresh_in_kg", "overlap_out", "burnt", "u", "cycle_work",
		"cycle_deg", "cycle_peak_p", "cycle_max_dp", "cycle_p", "ca10", "ca50", "ca90"]
	var s := PackedFloat64Array()
	s.resize(NAMES.size())
	for i in NAMES.size():
		var n: String = NAMES[i]
		if n == "tank_mass":
			s[i] = tank.mass_kg
		elif n != "out_work" and n != "out_fuel":
			s[i] = float(c.get("_" + n if priv.has(n) else n))
	return s
