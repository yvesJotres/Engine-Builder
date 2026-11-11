extends SceneTree

# Runs the automatic dyno on one bundled preset and prints the report. Writes .txt, .md and .csv files under user://dyno_reports.
# Run: godot --headless --path . -s tools/diagnostics/dyno_report.gd -- honda_cbr250rr_sp_qs


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var preset_id := args[0] if args.size() > 0 else "honda_cbr250rr_sp_qs"
	var spec := DynoRunner.spec_for(preset_id)
	if spec == null:
		print("Unknown preset: %s" % preset_id)
		quit(2)
		return
	var reference := OnlineDyno.for_preset(preset_id)
	var result := DynoRunner.run(spec, preset_id)
	var conditions := DynoReport.conditions(spec, preset_id, DynoRunner.display_name_for(preset_id))
	var report := DynoReport.build(result, conditions, reference, OnlineDyno.CALIBRATION_TOL)
	print(DynoReport.to_text(report))
	for path in DynoReport.write(report):
		print("wrote " + path)
	quit(0 if result.ok else 1)
