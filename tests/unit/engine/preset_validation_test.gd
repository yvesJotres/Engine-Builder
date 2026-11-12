extends SceneTree

# Every bundled preset must pass the engine's own validation. A preset that fails it shows a warning on the player's
# screen for a bike that is actually correct, and the warning never says which rule misfired.
# Run: godot --headless --path . -s tests/unit/engine/preset_validation_test.gd (prints PASS or FAIL)

var _fails := 0


func _init() -> void:
	await process_frame
	for id in Presets.PRESETS.keys():
		var p: Dictionary = Presets.PRESETS[id]
		var spec := EngineSpec.new()
		for key in p.keys():
			spec.set(key, p[key])
		check(spec.validation_warning() == "", "%s passes validation (%s)" % [id, spec.validation_warning()])

	# The rules must still catch a broken four-stroke, or passing above would mean nothing.
	var mt: Dictionary = Presets.PRESETS["yamaha_mt07"]
	var bad := EngineSpec.new()
	for key in mt.keys():
		bad.set(key, mt[key])
	bad.intake_duration_deg = 400.0
	check(bad.validation_warning() != "", "an impossible valve duration is still rejected")
	bad.intake_duration_deg = float(mt["intake_duration_deg"])
	bad.intake_lift_mm = 0.0
	check(bad.validation_warning() != "", "an impossible valve lift is still rejected")

	print("RESULT: " + ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(1 if _fails > 0 else 0)


func check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		_fails += 1
