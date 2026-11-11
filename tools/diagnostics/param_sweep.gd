extends SceneTree

# Sweeps one preset property over several values, runs the dyno for each, and scores the whole curve against the
# digitized reference (reports/cbr250rr_reference_curve.json). Nothing is written to the preset. Diagnostic only.
# Score = RMS relative error of wheel power (crank hp × 0.93) and of torque, over 5,000 to 13,000 rpm, in %.
# Run: godot --headless --path . -s tools/diagnostics/param_sweep.gd -- honda_cbr250rr_sp_qs wall_heat_scale 0.28 0.6 1.0

const REF_PATH := "res://reports/cbr250rr_reference_curve.json"
const EFF := 0.93


func _interp(points: Array, x: float) -> float:
	if x <= points[0][0]:
		return points[0][1]
	for i in range(1, points.size()):
		if points[i][0] >= x:
			var a: Array = points[i - 1]
			var b: Array = points[i]
			return a[1] + (b[1] - a[1]) * (x - a[0]) / (b[0] - a[0])
	return points[points.size() - 1][1]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var preset_id: String = args[0]
	var base: Dictionary = {}
	var positional: Array = []
	for i in range(1, args.size()):
		if "=" in args[i]:
			var kv: PackedStringArray = args[i].split("=")
			base[kv[0]] = float(kv[1])
		else:
			positional.append(args[i])
	var prop: String = positional[0]
	var values: Array = positional.slice(1)
	var ref: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(REF_PATH))
	var ref_power: Array = ref.power_hp
	var ref_torque: Array = ref.torque_nm
	print("%s on %s  (score = RMS error %%, lower is better)" % [prop, preset_id])
	print("value      score  power_err  torque_err  T@4k  T@6k  T@8k  T@10k T@11k T@13k  peak_wheel_hp@rpm")
	for v in values:
		var spec := DynoRunner.spec_for(preset_id)
		for k in base:
			spec.set(k, base[k])
		spec.set(prop, float(v) if str(v).is_valid_float() else v)
		var sim := EngineSim.new()
		sim.fuel.set_kind(spec.fuel)
		var dyno := DynoTest.new()
		dyno.reference_id = preset_id
		dyno.start(spec, sim)
		var frames := 0
		while dyno.active() and frames < 200000:
			dyno.advance(1.0 / 60.0, sim, spec, 1.0, true)
			frames += 1
		var curve: Array = []
		for p in dyno.result().curve:
			curve.append([p.rpm, p.torque, p.hp])
		var sim_power: Array = []
		var sim_torque: Array = []
		for c in curve:
			sim_power.append([c[0], c[2] * EFF])
			sim_torque.append([c[0], c[1]])
		var pe := 0.0
		var te := 0.0
		var n := 0
		var pe_mean := 0.0
		var te_mean := 0.0
		var rpm := 5000.0
		while rpm <= 13000.0:
			var rp := _interp(sim_power, rpm)
			var rr := _interp(ref_power, rpm)
			var tq := _interp(sim_torque, rpm)
			var tr := _interp(ref_torque, rpm)
			var ep := (rp - rr) / rr
			var et := (tq - tr) / tr
			pe += ep * ep
			te += et * et
			pe_mean += ep
			te_mean += et
			n += 1
			rpm += 100.0
		# power curve only: the reference's torque curve does not agree with its power curve (power = torque × rpm)
		var score := 100.0 * sqrt(pe / n)
		var peak: Dictionary = dyno.result().peak_hp
		print("%-9s %6.1f  %8.1f%%  %9.1f%%  %4.1f %4.1f %4.1f %5.1f %5.1f %5.1f   %5.1f@%5.0f" % [
			str(v), score, 100.0 * pe_mean / n, 100.0 * te_mean / n,
			_interp(sim_torque, 4000.0), _interp(sim_torque, 6000.0), _interp(sim_torque, 8000.0),
			_interp(sim_torque, 10000.0), _interp(sim_torque, 11000.0), _interp(sim_torque, 13000.0),
			float(peak.hp) * EFF, float(peak.rpm)])
	quit(0)
