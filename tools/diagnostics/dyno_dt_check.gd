extends SceneTree

# Runs the same dyno pull at different frame steps, to see how much the frame rate alone changes the curve.
# Diagnostic only. Run: godot --headless --path . -s tools/diagnostics/dyno_dt_check.gd -- honda_cbr250rr_2020

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var preset_id := args[0] if args.size() > 0 else "honda_cbr250rr_2020"
	var spec := DynoRunner.spec_for(preset_id)
	if spec == null:
		print("Unknown preset: %s" % preset_id)
		quit(2)
		return
	for warm in [false, true]:
		var dt := 1.0 / 60.0
		var sim := EngineSim.new()
		sim.fuel.set_kind(spec.fuel)
		if warm:
			sim.oil_c = spec.oil_operating_c # a machine that has been running warms its oil
		var dyno := DynoTest.new()
		dyno.reference_id = preset_id
		dyno.start(spec, sim)
		var frames := 0
		while dyno.active() and frames < DynoRunner.MAX_FRAMES:
			dyno.advance(dt, sim, spec, 1.0, true)
			frames += 1
		var r := dyno.result()
		var ph: Dictionary = r.get("peak_hp", {})
		var pt: Dictionary = r.get("peak_torque", {})
		print("warm=%s dt=1/%d frames=%d peak_hp=%.2f at %.0f rpm, peak_nm=%.2f at %.0f rpm" % [str(warm), int(round(1.0 / dt)), frames, float(ph.get("hp", 0.0)), float(ph.get("rpm", 0.0)), float(pt.get("torque", 0.0)), float(pt.get("rpm", 0.0))])
	quit(0)
