extends SceneTree

# Names the term that limits IMEP at high rpm on the litre bikes, to confirm or
# refute the burn-duration hypothesis before any constant is touched.
#
# For each rpm it warms, holds exactly 32 closed 720-deg cycles, then reads the
# last cycle's state straight off the cylinder: trapped air (VE), net IMEP, burn
# phasing (CA50/CA90/10-90), peak pressure, residual fraction, wall heat and lambda.
#
# The exhaust layout is attached exactly as the dyno gate does, so backpressure is in.
#
# Run:
#   godot --headless --path . -s res://tools/diagnostics/high_rpm_probe.gd -- --preset=honda_cbr1000rrr_sp --rpm=8000,10000,12000,13000,14000

const DT := 1.0 / 2400.0
const CYCLES := 32

var _preset := "honda_cbr1000rrr_sp"
var _rpms: Array = [8000, 10000, 12000, 13000, 14000]
var _hz := 2400.0
var _gd := false
var _measured: Dictionary = {}


func _build_spec() -> EngineSpec:
	var spec := EngineSpec.new()
	var preset: Dictionary = Presets.PRESETS[_preset]
	for key in preset:
		spec.set(key, preset[key])
	return spec


func _hold(spec: EngineSpec, rpm: float) -> Dictionary:
	var sim := EngineSim.new()
	sim.audio_enabled = false
	sim.physics_dt = 1.0 / _hz
	# Same exhaust layout the dyno gate builds: backpressure in, not a bare pipe.
	sim.set_audio_layout(ExhaustLayout.build(spec, [], Vector3(0.0, 2.0, 0.0), Ground.Y, Vector3(0.0, 3.0, -5.95)), spec.cylinders)
	var dt := sim.physics_dt

	# Warm one second at target speed.
	for i in int(1.0 / dt):
		sim.rpm = rpm
		sim.omega = rpm * TAU / 60.0
		sim.step(dt, spec, 1.0, true, false, true, false, 1.0)

	# Sample wall heat before the measured cycles.
	var wall_before := 0.0
	for c in sim.cylinders:
		wall_before += c.wall_loss_j

	# Integrate exactly 32 closed cycles.
	var angle := 0.0
	while angle < 720.0 * CYCLES:
		var before: float = sim.cylinders[0].phi
		sim.rpm = rpm
		sim.omega = rpm * TAU / 60.0
		sim.step(dt, spec, 1.0, true, false, true, false, 1.0)
		var step_angle := minf(sim.cylinders[0].phi - before, 720.0 * CYCLES - angle)
		assert(step_angle > 0.0, "fixed-speed probe stopped advancing")
		angle += step_angle

	var wall_after := 0.0
	for c in sim.cylinders:
		wall_after += c.wall_loss_j

	var c0 := sim.cylinders[0] as Cylinder
	return {
		"ve": sim.volumetric_efficiency(),
		"imep_bar": sim.imep_pa() / 1e5,
		"bmep_bar": sim.bmep_pa() / 1e5,
		"fmep_bar": sim.fmep_pa() / 1e5,
		"ca50": c0.last_ca50,
		"ca90": c0.last_ca90,
		"burn_10_90": c0.last_burn_10_90,
		"peak_p_bar": c0.last_peak_pressure / 1e5,
		"residual": c0.last_residual_fraction,
		"wall_j_cycle": (wall_after - wall_before) / (CYCLES * sim.cylinders.size()),
		"lambda": sim.o2_lambda(),
		"fresh_kg": c0.last_fresh_kg,
		"peak_temp_k": c0.last_peak_temp,
	}


func _load_measured() -> void:
	var path := "res://assets/dyno/%s.json" % _preset
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		return
	var data: Dictionary = JSON.parse_string(text)
	var by_rpm := {}
	for s in data.get("power_samples", []):
		by_rpm[int(round(float(s[0]) / 500.0) * 500.0)] = float(s[1])
	_measured = by_rpm


func _init() -> void:
	await process_frame
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--preset="):
			_preset = arg.substr(9)
		elif arg.begins_with("--rpm="):
			_rpms = []
			for t in arg.substr(6).split(","):
				_rpms.append(int(t))
		elif arg.begins_with("--hz="):
			_hz = float(arg.substr(5))
		elif arg == "--gd":
			_gd = true
	Cylinder.use_native = not _gd
	_load_measured()

	var spec := _build_spec()
	print("== %s  (redline %.0f)" % [_preset, spec.redline_rpm])
	print("   %6s %5s %6s %6s %6s %5s %5s %6s %6s %6s %5s %6s" % [
		"rpm", "VE%", "IMEP", "BMEP", "FMEP", "CA50", "CA90", "10-90", "pPeak", "resid", "wallJ", "lambda"])

	for rpm in _rpms:
		var r := _hold(spec, rpm)
		var meas: float = _measured.get(int(round(rpm / 500.0) * 500.0), 0.0)
		print("   %6.0f %5.0f %6.2f %6.2f %6.2f %5.1f %5.1f %6.1f %6.1f %5.1f%% %6.1f %6.3f  (meas %.1f hp)" % [
			rpm, r.ve * 100.0, r.imep_bar, r.bmep_bar, r.fmep_bar,
			r.ca50, r.ca90, r.burn_10_90, r.peak_p_bar, r.residual * 100.0,
			r.wall_j_cycle, r.lambda, meas])

	quit()
