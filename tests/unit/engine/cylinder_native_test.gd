extends SceneTree

# The native Cylinder kernel (gdextension/src/cylinder_kernel.cpp) must give the same answers as the GDScript loop.
# Runs the same engine twice, once on each path, through a start, part throttle, a closed throttle and a wide-open rev to the limiter.
#  - Each frame's torque, rpm and fuel level are compared. They must agree to REL_TOL for at least MIN_EXACT frames
#    (the whole run for a single cylinder).
#  - Past that, a 4-cylinder run may drift: the live step size switches at 8000 rpm, and a 1e-13 rounding difference can flip
#    that decision one step earlier or later, after which the two runs separate like any chaotic simulation. So the later part
#    is compared on the mean rpm over the wide-open stage, which must agree within AVG_TOL.
# Prints FAIL lines and exits non-zero on a mismatch. "-- --gd-twice" compares the GDScript path with itself.
# Run: godot --headless --path . -s tests/unit/engine/cylinder_native_test.gd
const PRESETS := ["honda_cbr150r", "kawasaki_zx25r", "ducati_panigale_v4"]
const MIN_EXACT := {"honda_cbr150r": 600, "kawasaki_zx25r": 150, "ducati_panigale_v4": 150}
const REL_TOL := 1.0e-6
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
