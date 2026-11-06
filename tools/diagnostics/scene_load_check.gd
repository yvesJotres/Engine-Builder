extends SceneTree

# Diagnostic: loads and instantiates every scene in the project and the autoload scripts, printing any failure. Print only.
func _init() -> void:
	await process_frame
	var failures := 0
	for path in ["res://scenes/bootstrap.tscn", "res://scenes/main.tscn", "res://scenes/launcher.tscn", "res://scenes/pause_menu.tscn"]:
		var packed = load(path)
		if packed == null:
			print("LOAD FAILED " + path)
			failures += 1
			continue
		var node = packed.instantiate()
		if node == null:
			print("INSTANTIATE FAILED " + path)
			failures += 1
			continue
		print("ok scene " + path)
		node.free()
	for path in ["res://scripts/updates/patcher.gd", "res://scripts/app/single_instance.gd", "res://scripts/user/server_settings.gd"]:
		var script = load(path)
		print(("ok script " if script != null else "MISSING script ") + path)
		if script == null:
			failures += 1
	print("RESULT scene check failures: %d" % failures)
	quit(failures)
