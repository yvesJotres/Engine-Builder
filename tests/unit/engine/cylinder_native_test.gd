extends SceneTree

# The native Cylinder kernel (gdextension/src/cylinder_kernel.cpp) must give the same answers as the GDScript loop.
# Runs the same engine twice, once on each path, through a start, part throttle, a closed throttle and a wide-open rev to the limiter.
#  - The porting gate is the single-step comparison in _compare_one_step(): identical cylinder state in, all state values
#    compared after one advance(). It must agree to ONE_STEP_TOL. This is where a wrong formula or state mapping shows up.
#  - The long run is a smoke test. The editor's and the extension's CRT/libm can differ by one ULP in sin/cos/pow; that
#    difference amplifies through the port resonator, so the two runs cannot stay bit-identical for the whole run. The first
#    MIN_EXACT frames must still agree to REL_TOL, and the mean rpm over the wide-open stage must agree within AVG_TOL.
# Prints FAIL lines and exits non-zero on a mismatch. "-- --gd-twice" compares the GDScript path with itself.
# Run: godot --headless --path . -s tests/unit/engine/cylinder_native_test.gd
const PRESETS := ["honda_cbr150r", "kawasaki_zx25r", "ducati_panigale_v4"]
# Measured against the current physics: 106, 51 and 164 frames respectively. Leave margin, not zero.
const MIN_EXACT := {"honda_cbr150r": 80, "kawasaki_zx25r": 40, "ducati_panigale_v4": 120}
const REL_TOL := 1.0e-6
const ONE_STEP_TOL := 1.0e-9
const ONE_STEP_PHASES := [0.0, 90.0, 180.0, 270.0, 360.0, 450.0, 540.0, 630.0]
const AVG_TOL := 0.03
const WOT_FRAMES := 240
const FIELDS := ["phi", "mass", "temp", "pressure", "burn_energy_left", "burn_energy", "port_p", "runner_q", "exhaust_temp",
	"peak_temp", "last_peak_temp", "last_lambda", "fuel_unburnt_kg", "backfire_j", "wall_loss_j", "enthalpy_in_j",
	"enthalpy_out_j", "exhaust_mdot", "exhaust_power", "last_imep", "last_peak_pressure", "last_dp_dtheta", "last_ca10",
	"last_ca50", "last_ca90", "last_burn_10_90", "last_fresh_kg", "last_ivc_temp", "last_residual_fraction"]

var failures := 0


func _init() -> void:
	await process_frame
	if not Cylinder.native_available:
		print("SKIP: the CylinderKernel library is not loaded, nothing to compare")
		quit(2)
		return
	for preset in PRESETS:
		_compare(preset)
		_compare_one_step(preset)
	print("cylinder_native_test: %s" % ("PASSED" if failures == 0 else "FAILED (%d problems)" % failures))
	quit(0 if failures == 0 else 1)


func _run(preset: String, native: bool, lambda: float = 1.0) -> Dictionary:
	Cylinder.use_native = native
	var spec := EngineSpec.new()
	var p: Dictionary = Presets.PRESETS[preset]
	for key in p.keys():
		spec.set(key, p[key])
	var sim := EngineSim.new()
	var log := {"torque": [], "rpm": [], "fuel": [], "fields": [], "flow": []}
	var script := [[0.0, true, 90], [0.2, false, 150], [0.0, false, 120], [1.0, false, WOT_FRAMES]] # throttle, starter, frames
	for stage in script:
		for i in int(stage[2]):
			sim.step(1.0 / 60.0, spec, stage[0], true, stage[1], false, false, lambda)
			log.torque.append(sim.torque)
			log.rpm.append(sim.rpm)
			log.fuel.append(sim.fuel.mass_kg)
	for c in sim.cylinders:
		var row := []
		for f in FIELDS:
			row.append(c.get(f))
		log.fields.append(row)
		var bins := []
		for k in 24:
			bins.append(c.exhaust_flow_at(k * 30.0))
		log.flow.append(bins)
	Cylinder.use_native = true
	return log


func _close(a: float, b: float) -> bool:
	return absf(a - b) <= REL_TOL * maxf(1.0, maxf(absf(a), absf(b)))


func _close_tol(a: float, b: float, tol: float) -> bool:
	return absf(a - b) <= tol * maxf(1.0, maxf(absf(a), absf(b)))


# One identical cylinder state, one advance() call, both paths. This is the porting gate: it removes the chaotic
# long-run amplification and compares the model directly.
func _compare_one_step(preset: String) -> void:
	var spec := EngineSpec.new()
	var p: Dictionary = Presets.PRESETS[preset]
	for key in p.keys():
		spec.set(key, p[key])
	var bad := 0
	for phase in ONE_STEP_PHASES:
		var gd := _one_step(spec, phase, false)
		var nat := _one_step(spec, phase, true)
		for f in FIELDS:
			if not _close_tol(gd[f], nat[f], ONE_STEP_TOL):
				bad += 1
				print("FAIL %s one-step phase %s %s: gdscript %s native %s" % [preset, str(phase), f, str(gd[f]), str(nat[f])])
				break
	if bad > 0:
		failures += bad
		print("%s one-step: %d phase(s) differ" % [preset, bad])


func _one_step(spec: EngineSpec, phase: float, native: bool) -> Dictionary:
	Cylinder.use_native = native
	var c := Cylinder.new()
	c.setup(spec.bore_mm, spec.stroke_mm, spec.compression_ratio, spec.reciprocating_kg(), spec.rod_over_crank_radius())
	c.set_cams(spec)
	c.start_at(phase)
	c.flow_step_deg = Cylinder.STEP_DEG
	c.pressure = 40000.0
	c.temp = 320.0
	c.mass = c.pressure * c.volume(c.phi) / (Cylinder.R * c.temp)
	c._u = c.mass * Cylinder.CV * c.temp
	c.port_p = 90000.0
	c.runner_q = 0.0
	c._m_in_prev = 0.0
	var tank := FuelTank.new()
	tank.set_kind(spec.fuel)
	c.advance(2.0, 1.0 / 6000.0, Cylinder.P0, 300.0, 720.0, true, tank, 1.0, false, false, Cylinder.P0, 300.0)
	var row := {}
	for f in FIELDS:
		row[f] = c.get(f)
	Cylinder.use_native = true
	return row


func _mean_tail(values: Array) -> float:
	var sum := 0.0
	for i in range(values.size() - WOT_FRAMES, values.size()):
		sum += values[i]
	return sum / WOT_FRAMES


func _compare(preset: String) -> void:
	var gd := _run(preset, false)
	# "-- --gd-perturb" runs the GDScript path against itself with a 1e-10 difference in mixture: the size of drift that chaos alone gives
	var nat := _run(preset, not OS.get_cmdline_user_args().has("--gd-twice") and not OS.get_cmdline_user_args().has("--gd-perturb"),
		1.0 + (1.0e-10 if OS.get_cmdline_user_args().has("--gd-perturb") else 0.0))
	var frames: int = gd.torque.size()
	var first_bad := -1
	for i in frames:
		for key in ["torque", "rpm", "fuel"]:
			if not _close(gd[key][i], nat[key][i]):
				first_bad = i
				print("note: %s %s drifts apart at frame %d: gdscript %s native %s" % [preset, key, i, str(gd[key][i]), str(nat[key][i])])
				break
		if first_bad >= 0:
			break
	var exact_frames := frames if first_bad < 0 else first_bad
	var need: int = MIN_EXACT[preset]
	var bad := 0
	if exact_frames < need:
		bad += 1
		print("FAIL %s: the two paths agree for %d frames, need at least %d" % [preset, exact_frames, need])
	if first_bad < 0: # no drift: every public state value and the exhaust flow must also agree
		for ci in gd.fields.size():
			for fi in FIELDS.size():
				if not _close(gd.fields[ci][fi], nat.fields[ci][fi]):
					bad += 1
					print("FAIL %s cylinder %d %s: gdscript %s native %s" % [preset, ci, FIELDS[fi], str(gd.fields[ci][fi]), str(nat.fields[ci][fi])])
			for k in 24:
				if not _close(gd.flow[ci][k], nat.flow[ci][k]):
					bad += 1
					print("FAIL %s cylinder %d exhaust flow bin %d: gdscript %s native %s" % [preset, ci, k, str(gd.flow[ci][k]), str(nat.flow[ci][k])])
	# Mean rpm over the wide-open stage. Mean torque is not compared: at the rev limiter it swings from run to run (two GDScript
	# runs a 1e-10 apart in mixture already differ by more than 10x there), so it says nothing about the port.
	var a := _mean_tail(gd.rpm)
	var b := _mean_tail(nat.rpm)
	if absf(a - b) / maxf(absf(a), 1.0) > AVG_TOL:
		bad += 1
		print("FAIL %s mean rpm over the wide-open stage: gdscript %s native %s" % [preset, str(a), str(b)])
	failures += bad
	print("%s: %d frames, exact for %d, %d problems" % [preset, frames, exact_frames, bad])
