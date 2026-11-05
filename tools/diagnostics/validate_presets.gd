extends SceneTree

# Diagnostic: runs EngineSpec.validation_warning() on every preset. Print only.
func _init() -> void:
	await process_frame
	for name in Presets.PRESETS.keys():
		var spec := EngineSpec.new()
		var p: Dictionary = Presets.PRESETS[name]
		for key in p.keys():
			spec.set(key, p[key])
		var w := spec.validation_warning()
		print("%-32s %s" % [name, w if w != "" else "ok"])
	quit(0)
