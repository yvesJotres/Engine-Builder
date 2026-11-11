extends SceneTree

# Prints the engine dropdown order exactly as the control panel sorts it. Diagnostic only.
# Run: godot --headless --path . -s tools/diagnostics/preset_order_check.gd

func _init() -> void:
	var library: Dictionary = Presets.PRESETS
	var keys := library.keys()
	keys.sort_custom(func(a, b): return str(library[a].get("display_name", a)).naturalnocasecmp_to(str(library[b].get("display_name", b))) < 0)
	for id in keys:
		print(library[id].get("display_name", id))
	quit(0)
