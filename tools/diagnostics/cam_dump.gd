extends SceneTree

# Prints the cam and valve settings of each preset that Cylinder.set_cams reads. Print only.
# Run: godot --headless --path . -s tools/diagnostics/cam_dump.gd
func _init() -> void:
	await process_frame
	for id in Presets.names():
		var spec := EngineSpec.new()
		var p: Dictionary = Presets.PRESETS[id]
		for key in p.keys():
			spec.set(key, p[key])
		print("%s: cyl %d profile %d/%d curves %d/%d ramps %s %s %s %s dur050 %s %s valve_cd %s" % [id, spec.cylinders,
			spec.intake_lobe_profile, spec.exhaust_lobe_profile, spec.intake_lift_curve.size(), spec.exhaust_lift_curve.size(),
			str(spec.intake_open_ramp_deg), str(spec.intake_close_ramp_deg), str(spec.exhaust_open_ramp_deg), str(spec.exhaust_close_ramp_deg),
			str(spec.intake_duration_050_deg), str(spec.exhaust_duration_050_deg), str(spec.valve_cd)])
	quit()
