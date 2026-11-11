extends SceneTree

# Runs the dyno for one attempt and prints the curve as CSV in the same format as dyno_curve_dump.gd.
# Options: path (native or gd); key=value overrides apply to the preset.
# Run: godot --headless --path . -s tools/diagnostics/dyno_attempt.gd -- honda_cbr250rr_2020 native intake_valve_mm=18


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var preset_id := args[0] if args.size() > 0 else "honda_cbr250rr_2020"
	var path := args[1] if args.size() > 1 else "native"
	Cylinder.use_native = path != "gd"
	var spec := DynoRunner.spec_for(preset_id)
	if spec == null:
		print("Unknown preset: %s" % preset_id)
		quit(2)
		return
	for i in range(2, args.size()):
		var kv: PackedStringArray = args[i].split("=")
		var key := kv[0]
		var value := float(kv[1])
		spec.set(key, value)
	var result := DynoRunner.run(spec, preset_id)
	print("rpm,torque_nm,hp,intake_pa,lambda,egt_c,bsfc_g_kwh,samples")
	for p in result.curve:
		print("%.0f,%.2f,%.2f,%.0f,%.3f,%.1f,%.1f,%.0f" % [p.rpm, p.torque, p.hp, p.intake_pa, p.lambda, p.egt_c, p.bsfc_g_kwh, p.samples])
	quit(0)
