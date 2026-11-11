extends SceneTree

# Prints a bundled preset's full dyno curve as CSV: torque, power, intake pressure, lambda and EGT per rpm bin.
# Diagnostic only. Run: godot --headless --path . -s tools/diagnostics/dyno_curve_dump.gd -- honda_cbr250rr_sp_qs


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var preset_id := args[0] if args.size() > 0 else "honda_cbr250rr_sp_qs"
	Cylinder.use_native = not (args.size() > 1 and args[1] == "gd")
	var spec := DynoRunner.spec_for(preset_id)
	if spec == null:
		print("Unknown preset: %s" % preset_id)
		quit(2)
		return
	var result := DynoRunner.run(spec, preset_id)
	print("rpm,torque_nm,hp,intake_pa,lambda,egt_c,bsfc_g_kwh,samples")
	for p in result.curve:
		print("%.0f,%.2f,%.2f,%.0f,%.3f,%.1f,%.1f,%.0f" % [p.rpm, p.torque, p.hp, p.intake_pa, p.lambda, p.egt_c, p.bsfc_g_kwh, p.samples])
	print("ambient_pa=%.0f" % float(result.ambient.pressure_pa))
	quit(0)
